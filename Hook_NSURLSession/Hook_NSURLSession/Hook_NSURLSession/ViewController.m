//
//  ViewController.m
//  Hook_NSURLSession
//
//  Created by ppsheep on 2018/3/6.
//  Copyright © 2018年 PPSHEEP. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://v.juhe.cn/toutiao/index"]];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSString *ss= [NSJSONSerialization JSONObjectWithData:data options:NSUTF8StringEncoding error:nil];
        NSLog(@"222");
    }];
    //    NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
    [task resume];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSLog(@"33");
}

@end
