//
//  ImageSender.h
//  Meemi
//
//  Created by Giacomo Tufano on 20/03/10.
//
//  Copyright 2011, Giacomo Tufano (gt@ilTofa.it)
//  Licensed under MIT license. See LICENSE file or http://www.opensource.org/licenses/mit-license.php
//

#import <UIKit/UIKit.h>
#import <MobileCoreServices/UTCoreTypes.h>

#import "Meemi.h"
#import "MeemiAppDelegate.h"

@protocol ImageSenderControllerDelegate

-(void)doneWithImageSender;

@end


@interface ImageSender : UIViewController <MeemiDelegate, UITextFieldDelegate, UIActionSheetDelegate, MeemiDelegate,
									UIImagePickerControllerDelegate, UINavigationControllerDelegate>
{
	UITextField *description;
	UITextField *locationLabel;
	UIImageView *theImageView;
	UIImage *theImage, *theThumbnail;
	UIActivityIndicatorView *laRuota;
	UISwitch *highResWanted;
	UISwitch *wantSave;
	id<ImageSenderControllerDelegate> delegate;
	BOOL comesFromCamera;
	NSNumber *replyTo;
	NSString *replyScreenName;
}

@property (retain, nonatomic) IBOutlet UITextField *description;
@property (retain, nonatomic) IBOutlet UITextField *locationLabel;
@property (retain, nonatomic) IBOutlet UIImageView *theImageView;
@property (retain, nonatomic) IBOutlet UIImage *theImage;
@property (retain, nonatomic) IBOutlet UIImage *theThumbnail;
@property (retain, nonatomic) IBOutlet UIActivityIndicatorView *laRuota;
@property (retain, nonatomic) IBOutlet UISwitch *highResWanted;
@property (retain, nonatomic) IBOutlet UISwitch *wantSave;
@property (assign) BOOL comesFromCamera;
@property (assign) id<ImageSenderControllerDelegate> delegate;
@property (retain, nonatomic) NSNumber *replyTo;
@property (retain, nonatomic) NSString *replyScreenName;

-(IBAction)sendIt:(id)sender;
-(IBAction)cancel:(id)sender;
-(void)showMediaPickerFor:(UIImagePickerControllerSourceType)type;

@end
