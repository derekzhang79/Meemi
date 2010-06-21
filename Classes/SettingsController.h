//
//  SettingsController.h
//  Meemi
//
//  Created by Giacomo Tufano on 17/03/10.
//  Copyright 2010 Giacomo Tufano (gt@ilTofa.it). All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Meemi.h"

@interface SettingsController : UIViewController <UITextFieldDelegate, MeemiDelegate>
{
	UITextField *screenName;
	UITextField *password;
	UILabel *testLabel;
	UIActivityIndicatorView *laRuota;
	UIButton *dismissButton;
}

@property (nonatomic, retain) IBOutlet UITextField *screenName;
@property (nonatomic, retain) IBOutlet UITextField *password;
@property (nonatomic, retain) IBOutlet UILabel *testLabel;
@property (nonatomic, retain) IBOutlet UIActivityIndicatorView *laRuota;
@property (nonatomic, retain) IBOutlet UIButton *dismissButton;

- (IBAction)testLogin:(id)sender;
- (IBAction)aboutBox:(id)sender;
- (IBAction)signupUser:(id)sender;
- (IBAction)dismissSettings:(id)sender;

@end
