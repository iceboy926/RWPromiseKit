//
// Created by deput on 3/12/16.
// Copyright (c) 2016 RW. All rights reserved.
//

#import "RWPromise.h"
#import "RWPromise+Internal.h"

@implementation RWPromise

#pragma mark - Class Methods
+ (RWPromise *)timeout:(NSTimeInterval)timeInSec {
    return [self promise:^(ResolveHandler resolve, RejectHandler reject) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (timeInSec * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            resolve(@"Timeout");
        });
    }];
}

+ (RWPromise *)promise:(RWPromiseBlock)block {
    return [[RWPromise alloc] init:block];
}

+ (RWPromise *)resolve:(id)value {
    if ([value isKindOfClass:[RWPromise class]]) {
        return value;
    } else {
        return [RWPromise promise:^(ResolveHandler resolve, RejectHandler reject) {
            resolve(value);
        }];
    }
}

+ (RWPromise *)reject:(id)value {
    if ([value isKindOfClass:[RWPromise class]]) {
        return value;
    } else {
        return [RWPromise promise:^(ResolveHandler resolve, RejectHandler reject) {
            reject([NSError errorWithDomain:@"RWPromise" code:1 userInfo:@{@"value" : value}]);
        }];
    }
}

#pragma mark - Instance Methods

- (instancetype)init:(RWPromiseBlock)initBlock {
    self = [super init];

    static int i = 0;
    i++;
    self.identifier = [@(i) stringValue];

    if (self) {
        self.state = RWPromiseStatePending;
        [self keepAlive];

        __weak RWPromise *wSelf = self;
        self.resolveBlock = ^(id value) {
            __strong RWPromise *sSelf = wSelf;
            STATE_PROTECT;
            if ([value isKindOfClass:[RWPromise class]]) {

                if (((RWPromise *) value).state == RWPromiseStatePending) {
                    sSelf.depPromise = value;
                    [value addObserver:sSelf forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
                } else {
                    //sSelf.depPromise = value;
                    [value addObserver:sSelf forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
                    //[sSelf losingControl];
                }
            } else {
                sSelf.value = value;
                sSelf.state = RWPromiseStateResolved;
                [sSelf losingControl];
            }
        };

        self.rejectBlock = ^(NSError *error) {
            __strong RWPromise *sSelf = wSelf;
            STATE_PROTECT;
            [sSelf losingControl];
            sSelf.error = error;
            NSLog(@"%@-%@", sSelf, [error description]);
            sSelf.state = RWPromiseStateRejected;
        };

        self.promiseBlock = initBlock;
    }

    [self run];
    return self;
}

- (void)keepAlive {
    self.strongSelf = self;
}

- (void)losingControl {
    self.strongSelf = nil;
}

- (void)dealloc {

    NSLog(@"dealloc");
    self.state = self.state;

    if (self.state == RWPromiseStatePending && self.depPromise) {
        if (self.depPromise.state == RWPromiseStateRejected) {
            if (self.catchBlock) {
                self.catchBlock(self.depPromise.error);
                self.resolveBlock(nil);
            } else {
                self.rejectBlock(self.depPromise.error);
            }


        } else if (self.depPromise.state == RWPromiseStateResolved) {
            //self.resolveBlock(self.depPromise.value);
            if (self.thenBlock) {
                if (self.thenBlock) {
                    self.thenBlock(self.depPromise.value);
                }
                self.resolveBlock(self.depPromise.value);
            }
        }

        //self.depPromise.state = self.depPromise.state;


    }
    self.depPromise = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"state"]) {
        RWPromiseState newState = [change[NSKeyValueChangeNewKey] unsignedIntegerValue];
        if (newState == RWPromiseStateRejected) {
            [object removeObserver:self forKeyPath:@"state"];
            if (self.catchBlock) {
                self.catchBlock([(RWPromise *) object error]);
                self.resolveBlock(nil);

            } else {
                self.rejectBlock([(RWPromise *) object error]);
            }

        } else if (newState == RWPromiseStateResolved) {
            [object removeObserver:self forKeyPath:@"state"];

            @try {
                if (self.thenBlock) {
                    self.thenBlock([(RWPromise *) object value]);
                }
                self.resolveBlock([(RWPromise *) object value]);
            }@catch(NSException *e){
                self.rejectBlock([NSError errorWithDomain:@"RWPromise" code:1 userInfo:@{@"exception":e}]);
            }
        }
    }
}

- (void)run {
    if (self.promiseBlock) {
        @try {
            self.promiseBlock(self.resolveBlock, self.rejectBlock);
        }
        @catch (NSException *e){
            self.rejectBlock([NSError errorWithDomain:@"RWPromise" code:1 userInfo:@{@"exception":e}]);
        }
    }
}
@end