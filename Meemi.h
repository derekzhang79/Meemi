//
//  Meemi.h
//  Meemi
//
//  Created by Giacomo Tufano on 18/03/10.
//  Copyright 2010 Giacomo Tufano (gt@ilTofa.it). All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@protocol MeemiDelegate;

typedef enum {
	MmRValidateUser = 1,
	MmRPostImage,
	MmRPostText
} MeemiRequest;

typedef enum
{
	MmUserExists = 0,
	MmWrongKey = 1,
	MmWrongPwd = 2,
	MmUserNotExists = 3,
	MmWrongMeme_type = 4,
	MmNoRecipientForPrivateMeme = 5,
	MmNoReplyAllowed = 6,
	MmPostOK = 7,
	MmNotLoggedIn = 8,
	MmMarked = 9,
	MmAddedToFavs = 10,
	MmDeletedFromFavs = 11,
	MmChanged = 12,
	MmNotYours = 13,
	MmMemeRemoved = 14,
	MmMemeDoNotExists = 15,
	MmUndefinedError = 999
} MeemiResult;

@interface Meemi : NSObject <CLLocationManagerDelegate>
{
	BOOL valid;
	NSString *screenName, *password;
	id<MeemiDelegate> delegate;
	MeemiRequest currentRequest;
	
	// for use by NSXMLParser and its delegates
	NSXMLParser *addressParser;
	NSMutableString *currentStringValue;
	NSMutableData *xmlData;

	NSURLConnection *theReverseGeoConnection;
	// How Many times have been denied Location use?
	double distance;
	BOOL needLocation;
	CLLocationManager *locationManager;
	int nLocationUseDenies;
	BOOL lcDenied;	
	NSString *placeName, *state;
	NSString *nearbyPlaceName;
}

@property (nonatomic, assign, getter=isLCDenied) BOOL lcDenied;
@property (nonatomic, assign) int nLocationUseDenies;
@property (nonatomic, getter=isValid) BOOL valid;
@property (nonatomic, copy) NSString *nearbyPlaceName;
@property (nonatomic, copy) NSString *screenName;
@property (nonatomic, copy) NSString *password;
@property (assign) id<MeemiDelegate> delegate;
@property (assign) MeemiRequest currentRequest;
@property (nonatomic, retain) NSString *placeName, *state;

+(Meemi *)sharedSession;

- (void)startLocation;

-(NSString *)getResponseDescription:(MeemiResult)response;
-(void)validateUser:(NSString *) meemi_id usingPassword:(NSString *)pwd;
-(void)postImageAsMeme:(UIImage *)image withDescription:(NSString *)description;
-(void)postTextAsMeme:(NSString *)description withChannel:(NSString *)channel withLocalization:(BOOL)canBeLocalized;

-(BOOL)parse:(NSData *)responseData;

@end

@protocol MeemiDelegate

-(void)meemi:(MeemiRequest)request didFailWithError:(NSError *)error;
-(void)meemi:(MeemiRequest)request didFinishWithResult:(MeemiResult)result;

@end
