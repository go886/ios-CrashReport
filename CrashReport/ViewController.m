//
//  ViewController.m
//  CrashReport
//
//  Created by go886 on 14/10/31.
//  Copyright (c) 2014年 go886. All rights reserved.
//

#import "ViewController.h"

NSString* trim(NSString* str) {
    return [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSString* runTask(NSString* path, ...) {
    NSMutableArray* array = [NSMutableArray array];
    va_list arg_ptr;
    va_start(arg_ptr, path);
    void *parameter = NULL;
    do {
        parameter = va_arg(arg_ptr, void *);
        if (parameter) [array addObject:((__bridge id)parameter)];
    } while (NULL != parameter);
    va_end(arg_ptr);
    
    //dwarfdump --uuid YourApp.app.dSYM
    //@"/usr/bin/dwarfdump"
    NSTask* task = [NSTask new];
    [task setLaunchPath:path];
    [task setArguments:array];
    
    NSPipe* pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    NSFileHandle* file = [pipe fileHandleForReading];
    [task launch];
    
    NSData* data = [file readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}


#define runDump(...) runTask(@"/usr/bin/dwarfdump", __VA_ARGS__, nil)

@interface DsymInfo : NSObject
@property(nonatomic,strong,readonly) NSString* path;
@property(nonatomic,strong,readonly) NSString* uuid;
@property(nonatomic,strong,readonly) NSString* cpuType;
@end

@implementation DsymInfo
-(instancetype)initWithPath:(NSString*)path {
    self = [super init];
    if (self) {
        _path = path;
        
        NSString* string = runDump(@"--uuid", path);
        NSError* err;
        NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"UUID:(.*?) \\((.*?)\\)"
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                              error:&err];
        if (re && !err) {
            NSTextCheckingResult* firstMatch = [re firstMatchInString:string
                                                              options:0
                                                                range:NSMakeRange(0, string.length)];
            if (firstMatch) {
                if (firstMatch.numberOfRanges == 3) {
                    _uuid = trim([string substringWithRange:[firstMatch rangeAtIndex:1]]);
                    _cpuType = [string substringWithRange:[firstMatch rangeAtIndex:2]];
                }
            }
        }
    }
    return self;
}
@end

@interface CrashInfo : NSObject
@property(nonatomic,strong,readonly) NSString* name;
@property(nonatomic,strong,readonly) NSString* uuid;
@property(nonatomic,strong,readonly) NSString* cpuType;
@property(nonatomic,strong,readonly) NSArray*  stackList;
@end

@implementation CrashInfo
-(instancetype)initWithInfo:(NSString*)info {
    self = [super init];
    if(self) {
        {
            //\nCPU Type: (.*?).*?Binary Image: (.*?)
            NSError* err;
            NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"dSYM UUID: (.*)\nCPU Type: (.*)\n.*?\nBinary Image: (.*)"
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:&err];
            if (re && !err) {
                NSTextCheckingResult* firstMatch = [re firstMatchInString:info
                                                                  options:0
                                                                    range:NSMakeRange(0, info.length)];
                if (firstMatch) {
                    if (firstMatch.numberOfRanges == 4) {
                        _uuid = trim([info substringWithRange:[firstMatch rangeAtIndex:1]]);
                        _cpuType = trim([info substringWithRange:[firstMatch rangeAtIndex:2]]);
                        _name = trim([info substringWithRange:[firstMatch rangeAtIndex:3]]);
                    }
                }
            }
        }
        
        if (!_name) {
            NSError* err;
            NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"Process:             (.*?) "
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:&err];
            if (re && !err) {
                NSTextCheckingResult* firstMatch = [re firstMatchInString:info
                                                                  options:0
                                                                    range:NSMakeRange(0, info.length)];
                if (firstMatch) {
                    if (firstMatch.numberOfRanges == 2) {
                        _name = trim([info substringWithRange:[firstMatch rangeAtIndex:1]]);
                    }
                }
            }
        }
        
        
        
        if (_name && _name.length) {
            //0x3517a3 walkman +
            //walkman                             0x23489
            NSError* err;
            NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"%@.*?0x(.*?) ", _name]
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:&err];
            if (re && !err) {
                NSArray* match = [re matchesInString:info options:NSMatchingReportCompletion range:NSMakeRange(0, info.length)];
                if (match.count) {
                    NSMutableArray* items = [NSMutableArray array];
                    for (NSTextCheckingResult* r in match) {
                        if (r.numberOfRanges == 2) {
                            [items addObject:[NSString stringWithFormat:@"0x%@", [info substringWithRange:[r rangeAtIndex:1]]]];
                        }
                    }
                    
                    _stackList = items;
                }
            }
        }
    }
    return self;
}
@end


@implementation ViewController {
    NSMutableDictionary* _dsymMap;
    CrashInfo*  _crashInfo;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"CrashReport";
    _dsymMap = [NSMutableDictionary dictionary];
    // Do any additional setup after loading the view.
    
    [self.crashTextView setDelegate:self];
    [self.stackTableView setDelegate:self];
    [self.stackTableView setDataSource:self];
    self.stackTableView.headerView.hidden = YES;
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
-(IBAction)onClick:(id)sender {
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    [oPanel setCanChooseDirectories:FALSE];
    [oPanel setAllowsMultipleSelection:YES];
    
    if (NSModalResponseOK == [oPanel runModalForTypes:@[@"dSYM"]]) {
        for (NSURL* url in [oPanel URLs]) {
            [self loadDSYM:url.path];
        }
       // [self loadDSYM:[[[oPanel URLs] objectAtIndex:0] path]];
    }
}

-(void)loadDSYM:(NSString*)path {
    DsymInfo* info = [[DsymInfo alloc] initWithPath:path];
    [_dsymMap setObject:info forKey:path];
    
    [self.field setStringValue:path];
    [self.titleField setStringValue:[NSString stringWithFormat:@"拷贝原始crash日志到这里 uuid(%@) cpu:%@", info.uuid, info.cpuType]];
}

-(DsymInfo*)findMatchDsym {
    for (NSString* key in _dsymMap) {
        DsymInfo* obj = _dsymMap[key];
        if ([obj.uuid isEqualToString:_crashInfo.uuid] && [obj.cpuType isEqualToString:_crashInfo.cpuType]) {
            return obj;
        }
    }
    
    return _dsymMap.count ? _dsymMap[_dsymMap.allKeys[0]] : nil;
}

-(void)dumpForAdd:(NSString*)addr {
    //dwarfdump –lookup 0x000036d2 –arch armv6 MyApp.app.dSYM
    DsymInfo* dsym = [self findMatchDsym];
    if (!dsym) {
        return;
    }
    
    NSString* string = runDump(@"--lookup", addr, @"-arch", dsym.cpuType, dsym.path);
    [self.resultTextView setString:string];
}

//NSTextViewDelegate
- (void)textDidChange:(NSNotification *)notification {
    NSString* str = self.crashTextView.string;
    _crashInfo = [[CrashInfo alloc] initWithInfo:str];
    [self.stackTableView reloadData];
}

#pragma  NSTableViewDelegate
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSIndexSet* indexSet = [self.stackTableView selectedRowIndexes];
    if (indexSet.count) {
        NSUInteger row = indexSet.firstIndex;
        NSString* addr = [_crashInfo.stackList objectAtIndex:row];
        [self dumpForAdd:addr];
        NSRange rng = [self.crashTextView.string rangeOfString:addr];
        [self.crashTextView setSelectedRange:rng];
        [self.crashTextView scrollRangeToVisible:rng];
    }
}

#pragma NSTableViewDataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _crashInfo.stackList.count;
}
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString* addr = [_crashInfo.stackList objectAtIndex:row];
    return addr;
   // return @{@"title": addr, @"name":@"a", @"objectValue": @"a"};
}
@end
