
### 网络层的数据的收集
网络层的数据，一般要收集的是API的请求频率、API请求时间、成功率等等信息。如果通过无埋的方式收集网络信息，肯定是通过AOP的方式，hook相应的方法和相应的delegate方法，来实现这一需求。

#### 针对NSURLSession进行网络数据的抓取
首先来分析一下通过NSURLSession发起的网络请求的流程：NSURLSession实际发起网络请求，是根据响应生成的[task resume]来开始网络请求的。

然后NSURLSession提供了两种方式来对请求的回调进行处理，一种是通过delegate来进行处理，还有一种就是通过block的方式，直接回调请求结果。

#### delegate回调方式
通过delegate回调方式来进行网络请求回调的处理，AFNetWorking通过NSURLSession发起的网络请求就是通过delegate来处理的，只是对外暴露的我们经常使用的是block的方式。

看一下NSURLSession的初始化方式和设置delegate的方式

```objc
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(nullable id <NSURLSessionDelegate>)delegate delegateQueue:(nullable NSOperationQueue *)queue;
```
提供的是两个类构造器，从上面两个构造的参数，我们能够猜出来，其实sessionWithConfiguration:最终也是调用sessionWithConfiguration:delegate:delegateQueu:方法，来初始化。一般我们把sessionWithConfiguration:delegate:delegateQueu:叫做工厂类方法。

还有一个方法，我们也经常用来获取session的实例，就是sharedSession，那这个获取的session和两个类构造器获取的session有什么不同呢？
其实我们在初始化session的时候，无论调用哪一个类构造器初始化session时，sharedSession都会调用sessionWithConfiguration:方法初始化一个单例session，但是这个单例的session有许多的限制，比如cookie、cache等，具体的说明，详见<https://developer.apple.com/documentation/foundation/nsurlsession/1409000-sharedsession>

什么意思呢？上面这么长一句。意思就是说，如果我们初始化了一个session，通过方法sessionWithConfiguration:，其实在NSURLSession内部会调用两次这个方法，第一次是我们主动调用生成一个session，返回给我们，另外一次就是sharedSession调用，生成一个系统默认的单例session，注意：因为这个sharedSession是一个单例的session，所以也就只有在首次生成session的时候，sharedSession会主动调用。当然，通过方法sessionWithConfiguration:delegate:delegateQueu:初始化session也是一样的。

为啥要说这么多，因为我们需要在session初始化的时候，做hook delegate的操作，因为NSURLSession的delegate是一个只读的属性，我们只能在初始化的时候来做hook处理

```objc
@property (nullable, readonly, retain) id <NSURLSessionDelegate> delegate;
```

#### hook delegate
首先考虑一下，我们有三个方法能够获取到session的实例，其实真正有delegate的只有一个构造方法，其他两个方法都没有delegate，那怎么做呢？

没有delegate的session是通过block回调方式拿到请求结果的，所以我们可以将session的含有block回调的方法hook掉，然后通过传入我们自己的block就能够拿到网络的回调结果了。

**注意：**如果一个session同时有delegate和block回调，那么delegate是不会被触发的，会直接回调到block里面，因为如果没有通过block回调来发起的请求，在session内部，实际上也是调用的含block的方法。这个在后面会详细介绍

还是看一下代码吧

首先介绍hook类构造器，达到hook delegate的效果。因为需要通过delegate拿到网络回调的类构造器只有sessionWithConfiguration:delegate:delegateQueue:方法，所以只需要将这个构造器hook掉，然后拿到delegate，然后再将delegate的对应的delegate方法hook掉就行

在NSURLSession的一个分类中，在load方法中，我们将sessionWithConfiguration:delegate:delegateQueue: hook

```objc
Hook_Method(cls, @selector(sessionWithConfiguration:delegate:delegateQueue:), cls, @selector(hook_sessionWithConfiguration:delegate:delegateQueue:),YES);
```

具体的hook实现方法,这个方法把hook类方法和hook实例方法都放在里面了，因为待会我们还要hook session的实例方法

```objc
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
```

然后在我们的hook实现方法中

```objc
+ (NSURLSession *)hook_sessionWithConfiguration: (NSURLSessionConfiguration *)configuration delegate: (id<NSURLSessionDelegate>)delegate delegateQueue: (NSOperationQueue *)queue {
    if (delegate) {
        Hook_Delegate_Method([delegate class], @selector(URLSession:dataTask:didReceiveData:), [self class], @selector(hook_URLSession:dataTask:didReceiveData:), @selector(none_URLSession:dataTask:didReceiveData:));
    }
    
    return [self hook_sessionWithConfiguration: configuration delegate: delegate delegateQueue: queue];
}
```
同样的，hook delegate的方法

```objc
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
```
**注意** 这里有一个地方需要注意，如果我们要hook的delegate有些方法没有实现，但是我们又想要hook掉这个方法，那么就需要先将delegate没有实现的方法 将它先添加进去，然后再将这个方法替换掉

然后在我们的替换类中实现相应的替换方法即可

```objc
- (void)hook_URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
         didReceiveData:(NSData *)data {
    [self hook_URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)none_URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
         didReceiveData:(NSData *)data {
    NSLog(@"11");
}
```

### 替换block回调

如果session没有通过delegate去拿到回调，那我们这时候需要怎么做呢？

如果不通过delegate拿，那就是session中一系列的含block的请求方法了，这些被称为 异步便利请求方法，全部定义在NSURLSession的一个分类中
NSURLSession (NSURLSessionAsynchronousConvenience)

```objc
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;
...
```

这里就举一个例子，来展示一下怎么hook 带block 参数的方法，其实也就是构造一个和参数一样的block，将自己的block传进去

同样的还是先将方法替换掉
```objc
Hook_Method(cls, @selector(dataTaskWithRequest:completionHandler:), cls, @selector(hook_dataTaskWithRequest:completionHandler:),NO);
```

然后，在我们hook的方法中

```objc
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
```

**注意** 这里需要判断当前的block是否存在，因为当我们将这个方法hook了以后，如果是当前的session是需要通过delegate来进行网络回调的，但是请求还是会走到我们hook的方法中，因为在session内部实现，我猜测应该是做了类似工厂方法的处理

所以这里判断如果block回调为空的时候，直接将nil传进去，这样就能够通过delegate拿到回调结果了

这里就简单举了一个带block参数的hook  其他的方法处理方式也是类似的，这里就不再一一列举了

这一篇主要讲的是hook系统的默认的http的请求方法，因为NSURLConnection已经废弃了，所以就没有做这个的hook，不过实现方式也是类似的

下一篇，我们将讲一下socket的hook，然后就再到view的圈选等等，这个系列会将无埋的一些主要的处理方式都分享出来。

另外：之前做这个hook的方式之前，也使用过NSURLProtocol来进行一些网络处理的拦截，但是因为涉及到多protocol的问题，因为目前项目中已经使用到了多个protocol，所以这种方式就抛弃了。而且，根据之前做的处理，NSURLProtocol要做的工作也不比这个少，所以就采用了AOP的方式

