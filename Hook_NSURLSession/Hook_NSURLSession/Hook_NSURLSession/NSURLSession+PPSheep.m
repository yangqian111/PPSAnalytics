//
//  NSURLSession+PPSheep.m
//  Hook_NSURLSession
//
//  Created by ppsheep on 2018/3/6.
//  Copyright © 2018年 PPSHEEP. All rights reserved.
//

#import "NSURLSession+PPSheep.h"
#import <objc/runtime.h>

//hook delegate方法
static void Hook_Delegate_Method(Class originalClass, SEL originalSel, Class replaceClass, SEL replaceSel, SEL noneSel) {
    Method originalMethod = class_getInstanceMethod(originalClass, originalSel);
    Method replaceMethod = class_getInstanceMethod(replaceClass, replaceSel);
    if (!originalMethod) {//没有实现delegate 方法
        Method noneMethod = class_getInstanceMethod(replaceClass, noneSel);
        BOOL didAddNoneMethod = class_addMethod(originalClass, originalSel, method_getImplementation(noneMethod), method_getTypeEncoding(noneMethod));
        if (didAddNoneMethod) {
            NSLog(@"没有实现的delegate方法添加成功");
        }
        return;
    }
    BOOL didAddReplaceMethod = class_addMethod(originalClass, replaceSel, method_getImplementation(replaceMethod), method_getTypeEncoding(replaceMethod));
    if (didAddReplaceMethod) {
        NSLog(@"hook 方法添加成功");
        Method newMethod = class_getInstanceMethod(originalClass, replaceSel);
        method_exchangeImplementations(originalMethod, newMethod);
    }
}

//Hook 方法
static void Hook_Method(Class originalClass, SEL originalSel, Class replaceClass, SEL replaceSel, BOOL isHookClassMethod) {
    
    Method originalMethod = NULL;
    Method replaceMethod = NULL;
    
    if (isHookClassMethod) {
        originalMethod = class_getClassMethod(originalClass, originalSel);
        replaceMethod = class_getClassMethod(replaceClass, replaceSel);
    } else {
        originalMethod = class_getInstanceMethod(originalClass, originalSel);
        replaceMethod = class_getInstanceMethod(replaceClass, replaceSel);
    }
    if (!originalMethod || !replaceMethod) {
        return;
    }
    IMP originalIMP = method_getImplementation(originalMethod);
    IMP replaceIMP = method_getImplementation(replaceMethod);
    
    const char *originalType = method_getTypeEncoding(originalMethod);
    const char *replaceType = method_getTypeEncoding(replaceMethod);
    
    //注意这里的class_replaceMethod方法，一定要先将替换方法的实现指向原实现，然后再将原实现指向替换方法，否则如果先替换原方法指向替换实现，那么如果在执行完这一句瞬间，原方法被调用，这时候，替换方法的实现还没有指向原实现，那么现在就造成了死循环
    if (isHookClassMethod) {
        Class originalMetaClass = objc_getMetaClass(class_getName(originalClass));
        Class replaceMetaClass = objc_getMetaClass(class_getName(replaceClass));
        class_replaceMethod(replaceMetaClass,replaceSel,originalIMP,originalType);
        class_replaceMethod(originalMetaClass,originalSel,replaceIMP,replaceType);
    } else {
        class_replaceMethod(replaceClass,replaceSel,originalIMP,originalType);
        class_replaceMethod(originalClass,originalSel,replaceIMP,replaceType);
    }
}

@implementation NSURLSession (PPSheep)

+ (void)load {
    Class cls = [self class];
    Hook_Method(cls, @selector(sessionWithConfiguration:delegate:delegateQueue:), cls, @selector(hook_sessionWithConfiguration:delegate:delegateQueue:),YES);
    
    Hook_Method(cls, @selector(dataTaskWithRequest:completionHandler:), cls, @selector(hook_dataTaskWithRequest:completionHandler:),NO);
    
}

+ (NSURLSession *)hook_sessionWithConfiguration: (NSURLSessionConfiguration *)configuration delegate: (id<NSURLSessionDelegate>)delegate delegateQueue: (NSOperationQueue *)queue {
    if (delegate) {
        Hook_Delegate_Method([delegate class], @selector(URLSession:dataTask:didReceiveData:), [self class], @selector(hook_URLSession:dataTask:didReceiveData:), @selector(none_URLSession:dataTask:didReceiveData:));
    }
    
    return [self hook_sessionWithConfiguration: configuration delegate: delegate delegateQueue: queue];
}

- (NSURLSessionDataTask *)hook_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    NSLog(@"33");
    
    void (^customBlock)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) = ^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (completionHandler) {
            completionHandler(data,response,error);
        }
        //做自己的处理
    };
    if (completionHandler) {
        return [self hook_dataTaskWithRequest:request completionHandler:customBlock];
    } else {
        return [self hook_dataTaskWithRequest:request completionHandler:nil];
    }
}

- (void)hook_URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
         didReceiveData:(NSData *)data {
    [self hook_URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)none_URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
         didReceiveData:(NSData *)data {
    NSLog(@"11");
}


@end
