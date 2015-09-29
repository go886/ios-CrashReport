//
//  ViewController.m
//  CrashReport
//
//  Created by go886 on 14/10/31.
//  Copyright (c) 2014年 go886. All rights reserved.
//

#import "ViewController.h"
#import <objc/message.h>

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

#define runAtos(...) runTask(@"/usr/bin/atos", __VA_ARGS__, nil)

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
                    _uuid = [[trim([string substringWithRange:[firstMatch rangeAtIndex:1]]) stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
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
@property(nonatomic,assign,readonly) BOOL isValid;
@end

@implementation CrashInfo
-(BOOL)isValid {
    return (_name && _uuid && _cpuType);
}
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
            NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"Process:(.*?)\n"
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:&err];
            
            
            if (re && !err) {
                NSTextCheckingResult* firstMatch = [re firstMatchInString:info
                                                                  options:0
                                                                    range:NSMakeRange(0, info.length)];
                if (firstMatch.numberOfRanges == 2) {
                    _name = trim([info substringWithRange:[firstMatch rangeAtIndex:1]]);
                    _name = [[_name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] objectAtIndex:0];
                }
            }
            
            if (_name) {
                re = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"Binary Images:.*?%@(.*?)<(.*?)>", _name]
                                                               options:NSRegularExpressionCaseInsensitive|NSRegularExpressionDotMatchesLineSeparators
                                                                 error:&err];
                
                if(re && !err) {
                    NSTextCheckingResult* firstMatch = [re firstMatchInString:info
                                                                      options:0
                                                                        range:NSMakeRange(0, info.length)];
                    if (firstMatch.numberOfRanges == 3) {
                        _cpuType = trim([info substringWithRange:[firstMatch rangeAtIndex:1]]);
                        _uuid = trim([info substringWithRange:[firstMatch rangeAtIndex:2]]);
                    }

                }
            }else {
                NSError* err;
                NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"Binary Images:\n.*? - .*? (.*?) (.*?) <(.*?)> "
                                                                                    options:NSRegularExpressionCaseInsensitive
                                                                                      error:&err];
                if (re && !err) {
                    NSTextCheckingResult* firstMatch = [re firstMatchInString:info
                                                                      options:0
                                                                        range:NSMakeRange(0, info.length)];
                    if (firstMatch) {
                        if (firstMatch.numberOfRanges == 4) {
                            _name = trim([info substringWithRange:[firstMatch rangeAtIndex:1]]);
                            _cpuType = trim([info substringWithRange:[firstMatch rangeAtIndex:2]]);
                            _uuid = trim([info substringWithRange:[firstMatch rangeAtIndex:3]]);
                        }
                    }
                }
            }
        }
        
        _uuid = [[_uuid stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
        
        if (_name && _name.length) {
            /*
            2 xiami                         	0x004e1369 0xc2000 + 4322153
             
            1. 模块号：这里是2
            2. 二进制库名：这里是xiami
            3. 调用方法的地址：这里是0x004e1369
            4. 第四部分分为两列，基地址和偏移地址。此处基地址为0xc2000，偏移地址为4322153。基地址指向crash的模块（也是模块的load地址）如UIKit。偏移地址指向crash代码的行数。
            */
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
    self.comboBox.delegate = self;
    
    [self searchDSYMPaths];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
-(void)searchDSYMPaths {
    NSString* s = runTask(@"/usr/bin/mdfind", @"-name", @".dSYM", nil);
    NSArray* paths = [s componentsSeparatedByString:@"\n"];
    [self.comboBox addItemsWithObjectValues:paths];
    for (NSString* path in paths) {
        if (![_dsymMap objectForKey:path]) {
            DsymInfo* info = [[DsymInfo alloc] initWithPath:path];
            [_dsymMap setObject:info forKey:path];
        }
    }
}
-(IBAction)onClick:(id)sender {
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    [oPanel setCanChooseDirectories:FALSE];
    [oPanel setAllowsMultipleSelection:YES];
    [oPanel setAllowedFileTypes:@[@"dSYM"]];
    
    [oPanel beginSheetModalForWindow:[self.view window] completionHandler:^(NSInteger result) {
        if (NSModalResponseOK == result) {
            for (NSURL* url in [oPanel URLs]) {
                [self loadDSYM:url.path];
            }
        }
    }];
//    if (NSModalResponseOK == [oPanel runModalForTypes:@[@"dSYM"]]) {
//        for (NSURL* url in [oPanel URLs]) {
//            [self loadDSYM:url.path];
//        }
//       // [self loadDSYM:[[[oPanel URLs] objectAtIndex:0] path]];
//    }
}

-(IBAction)onDumpAll:(id)sender {
    NSString* str = self.crashTextView.string;
    if (str && trim(str).length) {
            DsymInfo* dsym = [self findMatchDsym];
            if (!dsym) {
                [self.resultTextView setString:@"dSYM文件不匹配"];
                return;
            }
            
            [self.resultTextView setString:[self dumpAll:str dsym:dsym]];
    }
}


-(void)loadDSYM:(NSString*)path {
    DsymInfo* info = [[DsymInfo alloc] initWithPath:path];
    [_dsymMap setObject:info forKey:path];
    
    [self.comboBox setStringValue:path];
    //[self.field setStringValue:path];
    [self.titleField setStringValue:[NSString stringWithFormat:@"拷贝原始crash日志到这里 uuid(%@) cpu:%@", info.uuid, info.cpuType]];
}

-(DsymInfo*)findMatchDsym {
    for (NSString* key in _dsymMap) {
        DsymInfo* obj = _dsymMap[key];
        if ([obj.uuid isEqualToString:_crashInfo.uuid] && [obj.cpuType isEqualToString:_crashInfo.cpuType]) {
            return obj;
        }
    }
    
    return nil;
}

-(void)dumpForAdd:(NSString*)addr {
    //dwarfdump –lookup 0x000036d2 –arch armv6 MyApp.app.dSYM
    DsymInfo* dsym = [self findMatchDsym];
    if (!dsym) {
        [self.resultTextView setString:@"dSYM文件不匹配"];
        return;
    }
    
//    NSString* path = [dsym.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Contents/Resources/DWARF/%@", _crashInfo.name]];
//    NSString* string = runAtos(@"atos", @"-o", path, addr);
      NSString* string = runDump(@"--lookup", addr, @"-arch", dsym.cpuType, dsym.path, @"--uuid");
    [self.resultTextView setString:string];
}


-(NSString*)dumpAll:(NSString*)str dsym:(DsymInfo*)dsym {
    NSString* path = [dsym.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Contents/Resources/DWARF/%@", _crashInfo.name]];
    NSMutableString* outstring = [NSMutableString stringWithString:str];
    NSError* err;
    NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"^\\d+?\\s+(.*?)\\s+(.*?) "
                                                                        options:NSRegularExpressionCaseInsensitive|NSRegularExpressionAnchorsMatchLines
                                                                          error:&err];
    if (re && !err) {
        NSArray* match = [re matchesInString:str options:NSMatchingReportCompletion range:NSMakeRange(0, str.length)];
        if (match.count) {
            static char key;
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            for (NSTextCheckingResult* r in match) {
                NSString* bundleName = [str substringWithRange:[r rangeAtIndex:1]];
                if ([bundleName isEqualToString:_crashInfo.name]) {
                    NSString* addrName = [str substringWithRange:[r rangeAtIndex:2]];
                    [dict setObject:r forKey:addrName];
                }
            }
            [dict enumerateKeysAndObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSString*  _Nonnull addr, NSTextCheckingResult*  _Nonnull r, BOOL * _Nonnull stop) {
                NSString* expinfo = trim(runAtos(@"-o", path, addr, @"-arch", dsym.cpuType));
                // NSString* expinfo = trim(runDump(@"--lookup", addr, @"-arch", dsym.cpuType, dsym.path, @"--uuid"));
                objc_setAssociatedObject(r, &key, expinfo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }];
            
            NSEnumerator* itor = match.reverseObjectEnumerator;
            for (NSTextCheckingResult* r in itor) {
                NSString* addrName = [str substringWithRange:[r rangeAtIndex:2]];
                id obj = [dict objectForKey:addrName];
                if (obj) {
                    NSString* expinfo = objc_getAssociatedObject(obj, &key);
                    if (expinfo && expinfo.length && ![expinfo isEqualTo:addrName]) {
                        [outstring replaceCharactersInRange:[r rangeAtIndex:2] withString:expinfo];
                    }
                }
            }
        }
    }
    
    return outstring;
}

//NSTextViewDelegate
- (void)textDidChange:(NSNotification *)notification {
    NSString* str = self.crashTextView.string;
    if (str && trim(str).length) {
        _crashInfo = [[CrashInfo alloc] initWithInfo:str];
        if (_crashInfo.isValid) {
            self.logField.stringValue = [NSString stringWithFormat:@"日志信息: uuid(%@) cpu:%@  Process:%@",
                                         _crashInfo.uuid,
                                         _crashInfo.cpuType,
                                         _crashInfo.name];
            [self.stackTableView reloadData];
            //
            
            DsymInfo* dsym = [self findMatchDsym];
            if (!dsym) {
                [self.resultTextView setString:@"dSYM文件不匹配"];
                return;
            }
            return;
        }
    }
    
    [self.stackTableView reloadData];
    self.logField.stringValue = @"";
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
#pragma NSComboBoxDelegate
- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
    NSComboBox* comboBox = (NSComboBox*)notification.object;
    NSString* title = [comboBox stringValue];
    DsymInfo* info = [_dsymMap objectForKey:title];
    if (info) {
        [self.titleField setStringValue:[NSString stringWithFormat:@"拷贝原始crash日志到这里 uuid(%@) cpu:%@", info.uuid, info.cpuType]];
    }
}
@end
