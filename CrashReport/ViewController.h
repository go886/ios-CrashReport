//
//  ViewController.h
//  CrashReport
//
//  Created by go886 on 14/10/31.
//  Copyright (c) 2014年 go886. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController<NSTextViewDelegate, NSTableViewDelegate, NSTableViewDataSource>
@property(nonatomic,weak)IBOutlet NSTextField* field;
@property(nonatomic,weak)IBOutlet NSComboBox* comboBox;
@property(nonatomic,weak)IBOutlet NSTextField* titleField;
@property(nonatomic,weak)IBOutlet NSTextField* logField;
@property(nonatomic,strong)IBOutlet NSTextView* crashTextView;
@property(nonatomic,strong)IBOutlet NSTableView* stackTableView;
@property(nonatomic,strong)IBOutlet NSTextView* resultTextView;
@end

