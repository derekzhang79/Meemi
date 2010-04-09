//
//  UserProfile.h
//  Meemi
//
//  Created by Giacomo Tufano on 09/04/10.
//  Copyright 2010 Giacomo Tufano (gt@ilTofa.it). All rights reserved.
//

#import <UIKit/UIKit.h>
#import "User.h"

@interface UserProfile : UIViewController 
{
	User *theUser;
	UIImageView *theAvatar;
	UILabel *screenName, *realName, *since, *birth, *location, *info, *profile;
}

@property (nonatomic, retain) User *theUser;
@property (nonatomic, retain) IBOutlet UIImageView *theAvatar;
@property (nonatomic, retain) IBOutlet UILabel *screenName;
@property (nonatomic, retain) IBOutlet UILabel *realName;
@property (nonatomic, retain) IBOutlet UILabel *since;
@property (nonatomic, retain) IBOutlet UILabel *birth;
@property (nonatomic, retain) IBOutlet UILabel *location;
@property (nonatomic, retain) IBOutlet UILabel *info;
@property (nonatomic, retain) IBOutlet UILabel *profile;

@end
