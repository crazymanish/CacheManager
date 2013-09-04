//
//  CacheManager.m
//  
//
// Created by Manish Rathi on 03/09/13.
// Copyright (c) 2013 Manish Rathi
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "CacheManager.h"
#include <sys/xattr.h>

@interface CacheManager()
@property (nonatomic, strong) NSString *cacheDataPath;
@property (nonatomic, strong) NSOperationQueue *queue;
- (BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)fileURL;
@end

@implementation CacheManager
static CacheManager *sharedInstance = nil;

+ (id)instance{
    if (nil != sharedInstance) {
        return sharedInstance;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    if (self = [super init]) {
        //Init
        self.queue=[[NSOperationQueue alloc] init];
        [self createCacheDirectory];
    }
    return self;
}

#pragma mark - Create Cache Directory
-(BOOL)createCacheDirectory{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    self.cacheDataPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Cache"];
    /* check for existence of cache directory */
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.cacheDataPath]) {
        return YES;
    }
    NSError *error;
    /* create a new cache directory */
    return [[NSFileManager defaultManager] createDirectoryAtPath:self.cacheDataPath withIntermediateDirectories:NO attributes:nil error:&error];
}

#pragma mark - Clear Cache
- (BOOL)clearCache{
    NSError *error;
	/* remove the cache directory contents */
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *file in [fileManager contentsOfDirectoryAtPath:self.cacheDataPath error:&error]){
        NSString *filePath = [self.cacheDataPath stringByAppendingPathComponent:file];
        BOOL fileDeleted = [fileManager removeItemAtPath:filePath error:&error];
        if (fileDeleted != YES || error != nil){
            NSLog(@"File Not deleted for : %@", filePath);
        }else{
            NSLog(@"File deleted for : %@", filePath);
        }
    }
    return YES;
}

#pragma mark - iCloud BackUp Method
- (BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)fileURL
{
    // First ensure the file actually exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        NSLog(@"File %@ doesn't exist!",[fileURL path]);
        return NO;
    }
    
    const char* filePath = [[fileURL path] fileSystemRepresentation];
    const char* attrName = "com.apple.MobileBackup";
    if (&NSURLIsExcludedFromBackupKey == nil) {
        // iOS 5.0.1 and lower
        u_int8_t attrValue = 1;
        int result = setxattr(filePath, attrName, &attrValue, sizeof(attrValue), 0, 0);
        return result == 0;
    }
    else {
        // First try and remove the extended attribute if it is present
        int result = getxattr(filePath, attrName, NULL, sizeof(u_int8_t), 0, 0);
        if (result != -1) {
            // The attribute exists, we need to remove it
            int removeResult = removexattr(filePath, attrName, 0);
            if (removeResult == 0) {
                NSLog(@"Removed extended attribute on file %@", self);
            }
        }
        
        // Set the new key
        NSError *error = nil;
        BOOL success = [fileURL setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:&error];
        NSLog(@"succes: %i",success);
        if(!success){
            NSLog(@"Error excluding %@ from backup %@", [fileURL lastPathComponent], error);
        }
        
        return success;
    }
}

#pragma mark - Load Data
-(void)loadDatafromUrl:(NSURL *)_url onCompletionCallBack:(CacheManagerCompletionBlock)completionBlock{
    NSString *fileName = [[_url path] lastPathComponent];
	NSString *filePath = [self.cacheDataPath stringByAppendingPathComponent:fileName];
    // NSLog(@"IMAGE File-path= %@",filePath);
    NSData *fileData = [[NSData alloc] initWithContentsOfFile:filePath];
    if(fileData != nil){
        completionBlock(fileData);
    }else{
        NSURLRequest *request = [NSURLRequest requestWithURL:_url];
        [NSURLConnection sendAsynchronousRequest:request queue:self.queue completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
            [[NSFileManager defaultManager] createFileAtPath:filePath
                                                    contents:data
                                                  attributes:nil];
            if([self addSkipBackupAttributeToItemAtURL:[NSURL fileURLWithPath:filePath]]){
                completionBlock(data);
            }
        }];
    }
}
@end