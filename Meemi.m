//
//  Meemi.m
//  Meemi
//
//  Created by Giacomo Tufano on 18/03/10.
//
//  Copyright 2011, Giacomo Tufano (gt@ilTofa.it)
//  Licensed under MIT license. See LICENSE file or http://www.opensource.org/licenses/mit-license.php
//

#import "Meemi.h"
#import "MeemiAppDelegate.h"

#import "ASIFormDataRequest.h"
#import "ASINetworkQueue.h"

#import "SFHFKeychainUtils.h"

#import "UIImage+RoundedCorner.h"

// #import "FlurryAPI.h"

// for SHA-256
#include <CommonCrypto/CommonDigest.h>

// #define XMLLOG 1

#ifdef XMLLOG
#    define XLog(...) NSLog(__VA_ARGS__)
#else
#    define XLog(...) /* */
#endif

static Meemi *sharedSession = nil;

// Static variables for noting the common states
// ie
// Whatever is tied to the session in itself is on static variable accessed, if needed, from class methods
// Whatever is tied to the connection is in a standard property

// user credentials
NSString *screenName, *password;
// Session validity indicator
BOOL valid;
// CoreData hook
NSManagedObjectContext *managedObjectContext;
// Geolocation :)
NSString *nearbyPlaceName;
// Sessions active (used by isBusy)
int activeSessionsCount;
// page size for loading data
static int pageSize = 20;
static int replyPageSize = 20;

@implementation Meemi

@synthesize delegate, currentRequest;
@synthesize lcDenied, nLocationUseDenies, placeName, state;
@synthesize networkQueue;
@synthesize replyTo, replyUser;
@synthesize nextPageToLoad, lastReadMemeTimestamp;

#pragma mark Class Methods

#pragma mark Variable Access

+(NSString *)password
{
	return password;
}

+(void)setPassword:(NSString *)newValue
{
	if(password != newValue)
	{
		[password release];
		password = [newValue retain];
	}
}

+(NSString *)screenName
{
	return screenName;
}

+(void)setScreenName:(NSString *)newValue
{
	if(screenName != newValue)
	{
		[screenName release];
		screenName = [newValue retain];
	}
}

+(BOOL)isValid
{
	return valid;
}

+(NSManagedObjectContext *)managedObjectContext
{
	return managedObjectContext;
}

+(void)setManagedObjectContext:(NSManagedObjectContext *)newValue
{
	[managedObjectContext release];
	managedObjectContext = [newValue retain];
}

+(NSString *)nearbyPlaceName
{
	return nearbyPlaceName;
}

+(void)setNearbyPlaceName:(NSString *)newValue
{
	if(nearbyPlaceName != newValue)
	{
		[nearbyPlaceName release];
		nearbyPlaceName = [newValue retain];
	}
}

#pragma mark Class Status Query

+(BOOL)isBusy
{
	return activeSessionsCount > 0;
}

#pragma mark Singleton Class Setup

+(Meemi *)sharedSession
{
	@synchronized(self) {
        if (sharedSession == nil) {
            sharedSession = [[self alloc] init];
        }
    }
    return sharedSession;
}

//- (void)release
//{
//    //do nothing
//}
//
//- (id)autorelease
//{
//    return self;
//}

// init routine for use by sharedSession
-(id) init
{
	if((self = [super init]))
	{
		valid = NO;
		needLocation = YES;
		[Meemi setNearbyPlaceName:@""];
		// At the moment, user have not denied anything
		self.lcDenied = NO;
		// init the Queue
		theQueue = [[NSOperationQueue alloc] init];
		self.nextPageToLoad = 1;
		return self;
	}
	else
		return nil;
}

-(id)initFromUserDefault
{
	if((self = [super init]))
	{
		valid = NO;
		needLocation = YES;
		[Meemi setNearbyPlaceName:@""];
		// At the moment, user have not denied anything
		self.lcDenied = NO;
		// init the Queue
		theQueue = [[NSOperationQueue alloc] init];
		self.nextPageToLoad = 1;
		[Meemi setScreenName:[[NSUserDefaults standardUserDefaults] stringForKey:@"screenName"]];
		self.nLocationUseDenies = [[NSUserDefaults standardUserDefaults] integerForKey:@"userDeny"];
		NSError *err;
		[Meemi setPassword:[SFHFKeychainUtils getPasswordForUsername:[Meemi screenName] andServiceName:@"Meemi" error:&err]];
		if([Meemi password] != nil)
			valid = YES;
		else
		{
			DLog(@"invalid password for %@ is %@", [Meemi screenName], [Meemi password]);
			valid = NO;
		}
		return self;
	}
	else
		return nil;
}

-(void)nowBusy
{
	activeSessionsCount++;
	DLog(@"An I/O session started: count is %d", activeSessionsCount);
	if(activeSessionsCount == 1)
	{
		[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
		DLog(@"Notifying the world that we are now busy...");
		[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kNowBusy object:self]];
	}
}

-(void)nowFree
{
	activeSessionsCount--;
	DLog(@"An I/O session ended: count is %d", activeSessionsCount);
	if(activeSessionsCount <= 0)
	{
		activeSessionsCount = 0;
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		DLog(@"Notify the world that we are now free...");
		[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kNowFree object:self]];
	}
}

#pragma mark ASIHTTPRequest delegate

- (void)requestFinished:(ASIHTTPRequest *)request
{
	NSData *responseData = [request responseData];
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	if(self.currentRequest == MMMarkRead)
		DLog(@"Mark read finished, it's OK to pass");
	else
	{
		DLog(@"request sent and answer received. Calling parser for processing\n");
		[self parse:responseData];
	}
}

- (void)requestFailed:(ASIHTTPRequest *)request
{
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	[self nowFree];
	NSError *error = [request error];
	[self.delegate meemi:self.currentRequest didFailWithError:error];
}

+(void)returnOKFromRequestReturningStatus:(ASIHTTPRequest *)request
{
	NSString *retText = [[NSString alloc] initWithData:[request responseData] encoding:NSUTF8StringEncoding];
	NSRange statusRange = [retText rangeOfString:@"<status>1</status>"];
	// if there is not <status>1 we got an error
	if(statusRange.location == NSNotFound)
	{
		ALog(@"Got an error in a request:\n%@", retText);
		NSString *theMessage = [NSString stringWithFormat:NSLocalizedString(@"Error loading data: %@. Please try again later", @""), retText];
		UIAlertView *theAlert = [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", @"")
															message:theMessage
														   delegate:nil
												  cancelButtonTitle:@"OK" 
												  otherButtonTitles:nil] 
								 autorelease];
		[theAlert show];	
	}
	else
	{
		DLog(@"Succesfully returned from a request");
	}
	[retText release];	
}

+(void)returnFailedFromRequestReturningStatus:(ASIHTTPRequest *)request
{
	NSError *error = [request error];
	NSString *theMessage = [NSString stringWithFormat:NSLocalizedString(@"Error loading data: %@. Please try again later", @""),
							[error localizedDescription]];
	UIAlertView *theAlert = [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", @"")
														message:theMessage
													   delegate:nil
											  cancelButtonTitle:@"OK" 
											  otherButtonTitles:nil] 
							 autorelease];
	[theAlert show];	
}

#pragma mark Helpers

-(void)startSessionFromUserDefaults
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[Meemi setScreenName:[defaults stringForKey:@"screenName"]];
	self.nLocationUseDenies = [defaults integerForKey:@"userDeny"];
	NSError *err;
	[Meemi setPassword:[SFHFKeychainUtils getPasswordForUsername:[Meemi screenName] andServiceName:@"Meemi" error:&err]];
	if([Meemi password] == nil)
	{
		valid = NO;
		[defaults setInteger:0 forKey:@"userValidated"];
	}
	else
		valid = YES;
}

// Parse response string
// returns YES if xml parsing succeeds, NO otherwise
- (BOOL) parse:(NSData *)responseData
{
    if (addressParser) // addressParser is an NSXMLParser instance variable
        [addressParser release];
	addressParser = [[NSXMLParser alloc] initWithData:responseData];
	[addressParser setDelegate:self];
    [addressParser setShouldResolveExternalEntities:YES];
    if([addressParser parse])
		return YES;
	else
		return NO;
}

-(void)setupMemeRelationshipsFrom:(NSString *)name
{
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for an User with this screen_name.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"User" inManagedObjectContext:localManagedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"screen_name like %@", name];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [localManagedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		theUser = [fetchResults objectAtIndex:0];
	}
	else
	{
		// Create an User and add it to the managedObjectContext
		// (and to the list of "new ones" for later processing
		theUser = (User *)[NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:localManagedObjectContext];
		theUser.screen_name = name;
		[newUsersQueue addObject:name];
		DLog(@"New user created for %@", name);
	}
	// Whatever theUser is (new or pre-existing) now it's time to set the relationship with theMeme
	theMeme.user = theUser;
	[theUser addMemeObject:theMeme];
	[request release];
}

-(BOOL)isMemeAlreadyExisting:(NSNumber *)memeID
{
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for an User with this screen_name.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:localManagedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id == %@", memeID];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	BOOL retValue;
	NSArray *fetchResults = [localManagedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		// Set theMeme for further processing (if any)
		theMeme = [fetchResults objectAtIndex:0];
		// This is released at the end of the meme, if needed (if theMeme.new_meme is YES)
		retValue = YES;
	}
	else
		retValue = NO;
	[request release];
	return retValue;
}

#pragma mark Element end methods

-(void)parseElementsForMemes:(NSString *)elementName
{
	// id received, verify if the meme is new.
	if([elementName isEqualToString:@"id"])
	{
		newMemeID = [NSNumber numberWithLongLong:[currentStringValue longLongValue]];
		currentMemeIsNew = ![self isMemeAlreadyExisting:newMemeID];
		if(currentMemeIsNew)
		{
			DLog(@"*** got a new meme");
			theMeme = (Meme *)[NSEntityDescription insertNewObjectForEntityForName:@"Meme" inManagedObjectContext:localManagedObjectContext];
			theMeme.id = newMemeID;
			theMeme.new_meme = [NSNumber numberWithBool:YES];
		}
		else
		{
			DLog(@"*** Got an already read meme: %@", newMemeID);
		}
		// If it's a new mention or a new reply or a personal or a favorite mark it special (even if it's a "old one")
		if(self.currentRequest == MMGetNewMentions || self.currentRequest == MMGetNewPersonalReplies ||
           self.currentRequest == MMGetNewPersonals || self.currentRequest == MMGetNewFavorites)
		{
			DLog(@"Marking special the meme: %@", newMemeID);
			theMeme.special = [NSNumber numberWithBool:YES];
            // if the meme is not new but comes from a "newmentions" or "newreplies" mark it as "with new replies"
			if(!currentMemeIsNew && (self.currentRequest == MMGetNewMentions || self.currentRequest == MMGetNewPersonalReplies))
			{
				theMeme.new_replies = [NSNumber numberWithBool:YES];
				DLog(@"Marking with new replies the already read meme: %@", newMemeID);
			}
		}
	}
	// Other new memes things, only if the meme is new
	if(currentMemeIsNew)
	{
		// got a screen_name for a new meme. Setup relationship.
		if([elementName isEqualToString:@"screen_name"])
		{
			theMeme.screen_name = currentStringValue;
			[self setupMemeRelationshipsFrom:theMeme.screen_name];
		}
		if([elementName isEqualToString:@"date_time"])
		{
			NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setDateFormat:kNewMeemiDatesFormat];
			NSString *tempStringValue = [NSString stringWithFormat:@"%@+0000", [currentStringValue substringToIndex:[currentStringValue length] - 1]];
			theMeme.date_time = [dateFormatter dateFromString:tempStringValue];
			[dateFormatter release];
		}
		if([elementName isEqualToString:@"meme_type"])
		{
			theMeme.meme_type = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if(![theMeme.meme_type isEqualToString:@"text"])
				theMeme.content = [NSString stringWithFormat:@"This meme is a %@", theMeme.meme_type];
		}
		
		// Save recipient of private message (cut the ending ', ')
		if([elementName isEqualToString:@"user"])
			[sent_to appendFormat:@"%@, ", currentStringValue];
		if([elementName isEqualToString:@"sent_to"])
		{
			if(self.currentRequest != MMGetNewReplies)
			{
				// Workaround to protect the Veggyver crashes
				if(sent_to != nil && [sent_to length] > 2)
				{
					theMeme.sent_to = [sent_to substringToIndex:([sent_to length] - 2)];
					// It's private, I'm seeing it, so it must be special. :)
					theMeme.special = [NSNumber numberWithBool:YES];
				}
			}
			theMeme.private_meme = [NSNumber numberWithBool:YES];
		}
		
		if([elementName isEqualToString:@"content"])
			theMeme.content = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([elementName isEqualToString:@"location"])
			theMeme.location = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([elementName isEqualToString:@"posted_from"])
			theMeme.posted_from = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if([elementName isEqualToString:@"reply_screen_name"])
			theMeme.reply_screen_name = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([elementName isEqualToString:@"reply_id"])
			theMeme.reply_id = [NSNumber numberWithLongLong:[currentStringValue longLongValue]];
		
		if([elementName isEqualToString:@"avatar"] && theMeme.user.avatar == nil)
		{
			theMeme.user.avatar = [[currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] dataUsingEncoding:NSUTF8StringEncoding];
			theMeme.user.avatar_url = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		}
		// Here a meme is ended, should be saved.
		// For perfomance reason, we save at <memes/> below
		if([elementName isEqualToString:@"meme"])
		{
			// Workaround <replies>
			if(self.currentRequest == MMGetNewReplies)
			{
				if([theMeme.reply_id intValue] == 0)
					theMeme.reply_id = self.replyTo;
				if(theMeme.reply_screen_name == nil)
					theMeme.reply_screen_name = self.replyUser;
			}
			DLog(@"*** new meme ended ID: %@ ***", theMeme.id);
//			DLog(@"*** meme ended ***\n%@\n*** **** ***", theMeme);
		}
		// event meme_type
		if([elementName isEqualToString:@"name"])
			theMeme.event_name = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([elementName isEqualToString:@"when"])
		{
			NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setDateFormat:kNewMeemiDatesFormat];
			NSString *tempStringValue = [NSString stringWithFormat:@"%@+0000", [currentStringValue substringToIndex:[currentStringValue length] - 1]];
			theMeme.event_when = [dateFormatter dateFromString:tempStringValue];
			[dateFormatter release];
		}
		if([elementName isEqualToString:@"where"])
			theMeme.event_where = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		// image meme_type
		if([elementName isEqualToString:@"image"])
			theMeme.image_url = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([elementName isEqualToString:@"image_medium"])
			theMeme.image_medium_url = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([elementName isEqualToString:@"image_small"])
			theMeme.image_small_url = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		// quote meme_type
		if([elementName isEqualToString:@"source"])
			theMeme.quote_source = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		// link meme_type
		if([elementName isEqualToString:@"link"])
			theMeme.link = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		// video
		if([elementName isEqualToString:@"video"])
			theMeme.video = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	// Check for "our memes"
	if([elementName isEqualToString:@"screen_name"])
	{
		// if the meme is from ourselves, mark it "Special"
		if([currentStringValue caseInsensitiveCompare:[Meemi screenName]] == NSOrderedSame)
		{
			DLog(@"#found a meme from myself! Marking special");
			theMeme.special = [NSNumber numberWithBool:YES];
		}
	}
	
	// It's not a newMeme, but with different qta_reply?
	if([elementName isEqualToString:@"qta_replies"])
	{
		if([theMeme.qta_replies compare:[NSNumber numberWithLongLong:[currentStringValue longLongValue]]] == NSOrderedAscending)
		{
			theMeme.new_replies = [NSNumber numberWithBool:YES];
			DLog(@"### The meme have %d new reply(es).", [currentStringValue intValue] - [theMeme.qta_replies intValue]);
		}
		theMeme.qta_replies = [NSNumber numberWithLongLong:[currentStringValue longLongValue]];
	}
	// Get reshare and favorites state in any case, because we cannot easily check for the of our requests
	if([elementName isEqualToString:@"is_reshare"])
		theMeme.is_reshare = [NSNumber numberWithBool:[currentStringValue isEqualToString:@"1"]];
	if([elementName isEqualToString:@"is_preferite"])
		theMeme.is_favorite = [NSNumber numberWithBool:[currentStringValue isEqualToString:@"1"]];
	// Get the timestamp in any case for checking end (and set it just in case)
	if([elementName isEqualToString:@"dt_last_movement"])
	{
		NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateFormat:kNewMeemiDatesFormat];
		NSString *tempStringValue = [NSString stringWithFormat:@"%@+0000", [currentStringValue substringToIndex:[currentStringValue length] - 1]];
		theMeme.dt_last_movement = [dateFormatter dateFromString:tempStringValue];
		[dateFormatter release];
	}
	
	// Parsing ended: commit the CoreData objects to the db
	if([elementName isEqualToString:@"memes"] || [elementName isEqualToString:@"replies"])
	{
		// If we're parsing new memes, save last read timestamp of the meme (they're guaranteed to come in reverse date)
		if(self.currentRequest == MmGetNew)
			self.lastReadMemeTimestamp = [theMeme.dt_last_movement copy]; // !
		// Commit (if needed)
		NSError *error;
		if([localManagedObjectContext hasChanges])
		{
			if(self.currentRequest == MMGetNewReplies)
			{
				DLog(@"calling setWatermark: on delegate. Read %d records on a page of %d", howMany, replyPageSize);
				// Protect a bunch of unknown chrashes (not a solution, just a workaround)
				if([self.delegate respondsToSelector:@selector(setWatermark:)])
					[self.delegate setWatermark:howMany];
				else
					ALog(@"***!!!*** the delegate do not responds to setWatermark: ***!!!***");
			}
			else if(self.currentRequest == MmGetNew)
				// else get back the last loaded meme (0-based, so count is -1) 
				[self.delegate setWatermark:howMany * self.nextPageToLoad - 1];
			
			if (![localManagedObjectContext save:&error])
			{
				DLog(@"Failed to save to data store: %@", [error localizedDescription]);
				NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
				if(detailedErrors != nil && [detailedErrors count] > 0) 
					for(NSError* detailedError in detailedErrors) 
						DLog(@"  DetailedError: %@", [detailedError userInfo]);
				else 
					DLog(@"  %@", [error userInfo]);
				// Get back the error to the delegate
				[self.delegate meemi:self.currentRequest didFailWithError:error];
			}
		}
		DLog(@"Read %d records from page %d with %d new users", howMany, self.nextPageToLoad, [newUsersQueue count]);
		self.nextPageToLoad++;
		// now call update avatars (if needed, else get back to delegate)
		[self nowFree];
		if([newUsersQueue count] != 0)
			[self updateAvatars:NO];
		else // get back with watermark, before mark session free and release all.
		{
			[localManagedObjectContext release];
			localManagedObjectContext = nil;
			[self.delegate meemi:self.currentRequest didFinishWithResult:MmOperationOK];
		}
	}
}

-(void)parseElementsForUsers:(NSString *)elementName
{
	if([elementName isEqualToString:@"screen_name"])
	{
		NSString *name = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		ALog(@"Now looking for the user %@ for update", name);
		NSFetchRequest *request = [[NSFetchRequest alloc] init];
		// We're looking for an User with this screen_name.
		NSEntityDescription *entity = [NSEntityDescription entityForName:@"User" inManagedObjectContext:managedObjectContext];
		[request setEntity:entity];
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"screen_name like %@", name];
		[request setPredicate:predicate];
		// We're only looking for one.
		[request setFetchLimit:1];
		NSError *error;
		NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
		if (fetchResults != nil && [fetchResults count] != 0)
			theUser = [fetchResults objectAtIndex:0];
		else
			NSAssert(YES, @"user not found while it should be present");
		[request release];
	}
	if([elementName isEqualToString:@"current_location"])
		theUser.current_location = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if([elementName isEqualToString:@"real_name"])
	{
		theUser.real_name = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		DLog(@"Real name loaded: %@", theUser.real_name);
	}
	if([elementName isEqualToString:@"birth"])
	{
		NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateFormat:@"yyyy-MM-dd"];
		theUser.birth = [dateFormatter dateFromString:currentStringValue];
		[dateFormatter release];
	}
	if([elementName isEqualToString:@"description"])
		theUser.info = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if([elementName isEqualToString:@"profile"])
		theUser.profile = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if([elementName isEqualToString:@"you_follow"])
		theUser.you_follow = [NSNumber numberWithBool:[currentStringValue boolValue]];
	if([elementName isEqualToString:@"follow_you"])
		theUser.follow_you = [NSNumber numberWithBool:[currentStringValue boolValue]];
	if([elementName isEqualToString:@"qta_followings"])
		theUser.qta_followings = [NSDecimalNumber decimalNumberWithString:currentStringValue];
	if([elementName isEqualToString:@"qta_followers"])
		theUser.qta_followers = [NSDecimalNumber decimalNumberWithString:currentStringValue];
	if([elementName isEqualToString:@"user"])
	{
		NSError *error;
		if (![managedObjectContext save:&error])
		{
			DLog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					DLog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				DLog(@"  %@", [error userInfo]);
		}
		ALog(@"New user added %@", theUser.screen_name);
		[self.delegate meemi:MMGetNewUser didFinishWithResult:YES];
	}
}


#pragma mark NSXMLParser delegate

// NSXMLParser delegates

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
#ifdef XMLLOG
	XLog(@"Element Start: <%@>", elementName);
	NSEnumerator *enumerator = [attributeDict keyEnumerator];
	id key;
	while ((key = [enumerator nextObject])) 
	{
		XLog(@"attribute \"%@\" is \"%@\"", key, [attributeDict objectForKey:key]);
	}
#endif
	if([elementName isEqualToString:@"error"])
	{
		[self nowFree];
		[self.delegate meemi:self.currentRequest didFailWithError:nil];
	}
	if([elementName isEqualToString:@"message"])
	{
		// If it was a request for user validation, check return and inform delegate
		NSString *codeString = [attributeDict objectForKey:@"code"];
		int code = [codeString intValue];
		if(self.currentRequest == MmRValidateUser)
		{
			// if user is OK. Save it (both class and NSUserDefaults).
			valid = (code == MmUserExists);
			[self nowFree];
			[self.delegate meemi:self.currentRequest didFinishWithResult:code];
		}
		// If it was a  post, check return and inform delegate
		if(self.currentRequest == MmRPostImage || self.currentRequest == MmRPostText)
		{
			// if return code is OK, get back to delegate
			if(code == MmPostOK)
			{
				[self nowFree];
				[self.delegate meemi:self.currentRequest didFinishWithResult:code];
			}
		}
		// if it's a follow/unfollow request
		if(self.currentRequest == MMFollowUnfollow)
		{
			[self nowFree];
			// if return code is OK, get back to delegate
			if(code == MmFollowOK || code == MmUnfollowOK)
				[self.delegate meemi:self.currentRequest didFinishWithResult:code];
			else
				[self.delegate meemi:self.currentRequest didFailWithError:nil];				
		}
	}
	// parse memes
	if(self.currentRequest == MmGetNew || self.currentRequest == MMGetNewPvt || 
	   self.currentRequest == MMGetNewPvtSent || self.currentRequest == MMGetNewReplies ||
	   self.currentRequest == MMGetNewMentions || self.currentRequest == MMGetNewPersonalReplies ||
       self.currentRequest == MMGetNewPersonals || self.currentRequest == MMGetNewFavorites)
	{
		// Zero meme count in reply, to start counting
		if([elementName isEqualToString:@"memes"] || [elementName isEqualToString:@"replies"])
		{
			howMany = 0;
			// This is a good point to instantiate a local ManagedObjectContext if it not already exists
			if (localManagedObjectContext == nil)
			{
				
				NSPersistentStoreCoordinator *coordinator = [((MeemiAppDelegate *)[[UIApplication sharedApplication] delegate]) persistentStoreCoordinator];
				if (coordinator != nil) 
				{
					localManagedObjectContext = [[NSManagedObjectContext alloc] init];
					[localManagedObjectContext setPersistentStoreCoordinator:coordinator];
				}
			}			
		}
		// if a meme is coming increment meme count
		if([elementName isEqualToString:@"meme"])
			howMany++;		
		if([elementName isEqualToString:@"sent_to"])
		{
			if(sent_to != nil)
				[sent_to release];
			sent_to = [[NSMutableString alloc] initWithString:@""];
		}
	}
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string 
{
	XLog(@"Data: %@", string);
    if (!currentStringValue)
        // currentStringValue is an NSMutableString instance variable
        currentStringValue = [[NSMutableString alloc] initWithCapacity:256];
    [currentStringValue appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	XLog(@"Element End: %@", elementName);
	XLog(@"<%@> fully received with value: <%@>", elementName, currentStringValue);

	// new_memes processing 
	if(self.currentRequest == MmGetNew || self.currentRequest == MMGetNewPvt || 
	   self.currentRequest == MMGetNewPvtSent || self.currentRequest == MMGetNewReplies ||
	   self.currentRequest == MMGetNewMentions || self.currentRequest == MMGetNewPersonalReplies ||
       self.currentRequest == MMGetNewPersonals || self.currentRequest == MMGetNewFavorites)
		[self parseElementsForMemes:elementName];
	
    if ([elementName isEqualToString:@"name"])
		self.placeName = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if ([elementName isEqualToString:@"countryName"])
		self.state = [currentStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if ([elementName isEqualToString:@"distance"])
		sscanf([currentStringValue cStringUsingEncoding:NSASCIIStringEncoding], "%lf", &distance);

	// users processor
	if(self.currentRequest == MMGetNewUser)
		[self parseElementsForUsers:elementName];
    // reset currentStringValue for the next cycle
    [currentStringValue release];
    currentStringValue = nil;
}

#pragma mark API

+(NSString *)getResponseDescription:(MeemiResult)response
{
	NSString *ret;
	switch (response) 
	{
		case MmUserExists:
			ret = NSLocalizedString(@"User valid", @"");
			break;
		case MmWrongKey:
			ret = NSLocalizedString(@"Key not valid", @"");
			break;
		case MmWrongPwd:
			ret = NSLocalizedString(@"meemi_id or pwd not valid.", @"");
			break;
		case MmUserNotExists:
			ret = NSLocalizedString(@"User do not exists or is not active.", @"");
			break;
		case MmNoRecipientForPrivateMeme:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmNoReplyAllowed:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmPostOK:
			ret = NSLocalizedString(@"Post successful", @"");
			break;
		case MmNotLoggedIn:
			ret = NSLocalizedString(@"User not logged", @"");
			break;
		case MmMarked:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmAddedToFavs:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmDeletedFromFavs:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmChanged:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmNotYours:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmMemeRemoved:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmMemeDoNotExists:
			ret = [NSString stringWithFormat:NSLocalizedString(@"Error %d", @""), response];
			break;
		case MmUndefinedError:
			ret = NSLocalizedString(@"Undefined error.", @"");
			break;
		case MmFollowOK:
			ret = NSLocalizedString(@"Ok, you follow this user", @"");
			break;
		case MmUnfollowOK:
			ret = NSLocalizedString(@"Ok, you not follow this user", @"");
			break;
		default:
			ret = [NSString stringWithFormat:NSLocalizedString(@"REALLY undefined error: %d", @""), response];
			break;
	}
	return ret;
}

-(void)startRequestToMeemi:(ASIFormDataRequest *)request
{
	// build the password using SHA-256
	unsigned char hashedChars[32];
	CC_SHA256([[Meemi password] UTF8String],
			  [[Meemi password] lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 
			  hashedChars);
	NSString *hashedData = [[NSData dataWithBytes:hashedChars length:32] description];
    hashedData = [hashedData stringByReplacingOccurrencesOfString:@" " withString:@""];
    hashedData = [hashedData stringByReplacingOccurrencesOfString:@"<" withString:@""];
    hashedData = [hashedData stringByReplacingOccurrencesOfString:@">" withString:@""];	
	[request setPostValue:[Meemi screenName] forKey:@"meemi_id"];
	[request setPostValue:hashedData forKey:@"pwd"];
	[request setPostValue:kAPIKey forKey:@"app_key"];
	[request setDelegate:self];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
	if([request respondsToSelector:@selector(setShouldContinueWhenAppEntersBackground)])	
		[request setShouldContinueWhenAppEntersBackground:YES];
#endif
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	[self nowBusy];
	[request startAsynchronous];			
}

// Validates user and pwd, write them into appdefaults
-(void)validateUser:(NSString *) meemi_id usingPassword:(NSString *)pwd
{
	// Sanity checks
	NSAssert(delegate, @"delegate not set in Meemi");
	// Remember user and pwd in our structures
	[Meemi setScreenName:meemi_id];
	[Meemi setPassword:pwd];
	// Set current request type
	self.currentRequest = MmRValidateUser;
	
	// API for user testing
	NSURL *url = [NSURL URLWithString:@"http://meemi.com/api/p/exists"];
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];
}

-(void)followOrUnfollow:(NSString *)user isFollow:(BOOL)follow
{
	// Sanity checks
	NSAssert(delegate, @"delegate not set in Meemi");
	// Set current request type
	self.currentRequest = MMFollowUnfollow;
	
	// API for user testing
	NSString *stringUrl = [NSString stringWithFormat:@"http://meemi.com/api/%@/%@/%@", [Meemi screenName], follow ? @"follow" : @"unfollow", user];
	NSURL *url = [NSURL URLWithString:stringUrl];
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];
}

-(void)followUser:(NSString *)user
{
	[self followOrUnfollow:user isFollow:YES];
}

-(void)unfollowUser:(NSString *)user
{
	[self followOrUnfollow:user isFollow:NO];	
}

- (void)queueFinished:(ASINetworkQueue *)queue
{
	// You could release the queue here if you wanted
	if ([[self networkQueue] requestsCount] == 0) 
	{
		[self setNetworkQueue:nil]; 
		[self.networkQueue release];
	}
	ALog(@"Queue finished");
	// What read were the new users, save modifications and release the array...
	NSError *error;
	if (![managedObjectContext save:&error])
	{
		DLog(@"Failed to save to data store: %@", [error localizedDescription]);
		NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
		if(detailedErrors != nil && [detailedErrors count] > 0) 
			for(NSError* detailedError in detailedErrors) 
				DLog(@"  DetailedError: %@", [detailedError userInfo]);
		else 
			DLog(@"  %@", [error userInfo]);
	}
	[newUsersQueue release];
	newUsersQueue = nil;
	[self nowFree];
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	// OK. Now get avatar images.
	[self updateAvatars:NO];
}

-(void)getAvatarImageIfNeeded:(NSString *)userScreenName
{
	NSURL *url;
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"User" inManagedObjectContext:localManagedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"screen_name == %@", userScreenName];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [localManagedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		User *theOne = [fetchResults objectAtIndex:0];
		NSString *temp = [[NSString alloc] initWithData:theOne.avatar encoding:NSUTF8StringEncoding];
		if((url = [NSURL URLWithString:temp]) != nil)
		{
			NSError *error;
			// get avatar and store it
			DLog(@"getting avatar for %@ from %@", theOne.screen_name, temp);
			ASIHTTPRequest *netRequest = [ASIHTTPRequest requestWithURL:url];
			if([NSThread isMainThread])
				ALog(@"****!!!!**** we're blocking the main thread! ****!!!!****");
			
			[netRequest startSynchronous];
			error = [netRequest error];
			if (!error) {
				theOne.avatar = [netRequest responseData];
				UIImage *tempImage;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
				if([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
					tempImage = [[UIImage alloc] initWithCGImage:[[UIImage imageWithData:[netRequest responseData]] CGImage] 
														   scale:[[UIScreen mainScreen] scale]
													 orientation:UIImageOrientationUp];
				else
#endif
					tempImage = [[UIImage alloc] initWithCGImage:[[UIImage imageWithData:[netRequest responseData]] CGImage]];
				theOne.avatar_44 = UIImagePNGRepresentation([[tempImage squaredThumbnail:kAvatar44] roundedCornerImage:6 borderSize:1]);
//				DLog(@"1->image size: %f, %f. Scale: %f", tempImage.size.width, tempImage.size.height, tempImage.scale);
				[tempImage release];
			}		
			else {
				ALog(@"Error %@ in getting %@", [error localizedDescription], temp);
			}
		}
		[temp release];
	}
	[request release];
	
	if([localManagedObjectContext hasChanges])
	{
		NSError *error;
		if (![localManagedObjectContext save:&error])
		{
			ALog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					ALog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				ALog(@"  %@", [error userInfo]);
		}	
		DLog(@"saved %@", userScreenName);
	}
	else {
		DLog(@"No needs to save %@", userScreenName);
	}
}

-(void)getAvatarImage:(NSString *)userScreenName
{
	NSURL *url;
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"User" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"screen_name == %@", userScreenName];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		User *theOne = [fetchResults objectAtIndex:0];
		if((url = [NSURL URLWithString:theOne.avatar_url]) != nil)
		{
			NSError *error;
			// get avatar and store it
			DLog(@"getting (in any case) avatar for %@ from %@", theOne.screen_name, theOne.avatar_url);
			ASIHTTPRequest *netRequest = [ASIHTTPRequest requestWithURL:url];
			[netRequest startSynchronous];
			error = [netRequest error];
			if (!error) {
				theOne.avatar = [netRequest responseData];
				UIImage *tempImage;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
				if([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
					tempImage = [[UIImage alloc] initWithCGImage:[[UIImage imageWithData:[netRequest responseData]] CGImage] 
														   scale:[[UIScreen mainScreen] scale]
													 orientation:UIImageOrientationUp];
				else
#endif
					tempImage = [[UIImage alloc] initWithCGImage:[[UIImage imageWithData:[netRequest responseData]] CGImage]]; 
				theOne.avatar_44 = UIImagePNGRepresentation([[tempImage squaredThumbnail:kAvatar44] roundedCornerImage:6 borderSize:1]);
				[tempImage release];
			}		
			else {
				ALog(@"Error %@ in getting %@", [error localizedDescription], theOne.avatar_url);
			}
		}
	}
	[request release];
	
	if([managedObjectContext hasChanges])
	{
		NSError *error;
		if (![managedObjectContext save:&error])
		{
			ALog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					ALog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				ALog(@"  %@", [error userInfo]);
		}	
		DLog(@"saved %@", userScreenName);
	}
	else {
		DLog(@"No needs to save %@", userScreenName);
	}
}


-(void)getBackToDelegateAfterUpdateAvatars:(id)theDelegate
{
	DLog(@"in getBackToDelegateAfterUpdateAvatars:");
	// Cleanup
	[self nowFree];
	[localManagedObjectContext release];
	localManagedObjectContext = nil;
	[self.delegate meemi:self.currentRequest didFinishWithResult:MmOperationOK];
}

-(void)updateAvatars:(BOOL)forcedReload
{
	[theQueue setMaxConcurrentOperationCount:1];
	DLog(@"Loading NSOperationQueue in updateAvatars:%@", (forcedReload) ? @"YES" : @"NO");
	[self nowBusy];
//	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	for(NSString *newUser in newUsersQueue)
	{
		NSInvocationOperation *theOp = [[[NSInvocationOperation alloc] initWithTarget:self 
																			 selector:(forcedReload) ? @selector(getAvatarImage:)
																									 : @selector(getAvatarImageIfNeeded:)
																			   object:newUser] autorelease];
		[theQueue addOperation:theOp];
	}
	// The last operation get back to the delegate...
	NSInvocationOperation *theOp = [[[NSInvocationOperation alloc] initWithTarget:self 
																		 selector:@selector(getBackToDelegateAfterUpdateAvatars:) 
																		   object:self.delegate] autorelease];
	[theQueue addOperation:theOp];

	// reset newUsersQueue
	if(newUsersQueue)
	{
		[newUsersQueue release];
		newUsersQueue = nil;
	}
}

-(void)allAvatarsReload
{
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"User" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		// Load all screen_names in newUserQueue (so to force update as they were new)
		if(newUsersQueue)
		{
			[newUsersQueue release];
			newUsersQueue = nil;
		}
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:[fetchResults count]];		
		for (User *theOne in fetchResults) 
			[newUsersQueue addObject:theOne.screen_name];
	}
	[request release];
	// now load them
	[self updateAvatars:YES];
}

-(void)loadAvatar:(NSString *)screen_name
{
	[theQueue setMaxConcurrentOperationCount:1];
	DLog(@"Loading NSOperationQueue in loadAvatar");
	self.currentRequest = MMGetAvatar;
	// load the requested avatar...
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	NSInvocationOperation *theOp = [[[NSInvocationOperation alloc] initWithTarget:self 
																		 selector:@selector(getAvatarImage:) 
																		   object:screen_name] autorelease];
	[theQueue addOperation:theOp];
	// ...then get back to the delegate...
	theOp = [[[NSInvocationOperation alloc] initWithTarget:self 
												  selector:@selector(getBackToDelegateAfterUpdateAvatars:) 
													object:self.delegate] autorelease];
	[theQueue addOperation:theOp];
}

-(void)getUser:(NSString *)withName
{
	self.currentRequest = MMGetNewUser;
	NSURL *url = [NSURL URLWithString:
				  [NSString stringWithFormat:@"http://meemi.com/api3/%@/profile", withName]];
	
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	DLog(@"Requesting user %@ profile", withName);
	[self startRequestToMeemi:request];
}

-(void)getNewMemesRepliesOf:(NSNumber *)memeID screenName:(NSString *)user from:(int)startMeme number:(int)nMessagesToRetrieve
{
	NSAssert([Meemi isValid], @"getNewMemesRepliesOf:from:number:");
	self.currentRequest = MMGetNewReplies;
	
	// Now setup the URI depending on the request
	// http://meemi.com/api3/capobecchino/1010224/replies/-/10
	
	// Workaround <replies> data...
	self.replyTo = memeID;
	self.replyUser = user;
	// Init user DB
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSString *urlString = [NSString stringWithFormat:@"http://meemi.com/api3/%@/%@/replies/%@/%d", 
						   user, memeID, (startMeme == 0) ? @"-" : [[NSNumber numberWithInt:startMeme] stringValue], nMessagesToRetrieve];
	NSURL *url = [NSURL URLWithString:urlString];
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];
}

-(void)getMemeRepliesOf:(NSNumber *)memeID screenName:(NSString *)user total:(int)repliesQuantity
{
	NSAssert([Meemi isValid], @"getNewMemesRepliesOf:from:number:");
	self.currentRequest = MMGetNewReplies;
	// Workaround <replies> data...
	self.replyTo = memeID;
	self.replyUser = user;
	// Init user DB
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSString *urlString;
	if(repliesQuantity <= 20 || self.nextPageToLoad == 1)
	{
		urlString = [NSString stringWithFormat:@"http://meemi.com/api3/%@/%@/replies/-/%d", user, memeID, replyPageSize];
	}
	else
	{
		int startMeme = repliesQuantity - (pageSize * self.nextPageToLoad);
		if(startMeme < 0)
			startMeme = 1;
		urlString = [NSString stringWithFormat:@"http://meemi.com/api3/%@/%@/replies/%d/%d", user, memeID, startMeme, replyPageSize];
	}		
	
	NSURL *url = [NSURL URLWithString:urlString];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

-(void)getMemes
{
	NSAssert([Meemi isValid], @"getMemes: called without valid session");
	self.currentRequest = MmGetNew;
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSURL *url = [NSURL URLWithString:
				  [NSString stringWithFormat:@"http://meemi.com/api3/%@/wf/limit_%d/page_%d", 
				   [Meemi screenName], pageSize, self.nextPageToLoad]];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

-(void)getMemePrivateReceived
{
	NSAssert([Meemi isValid], @"getMemePrivateReceived: called without valid session");
	self.currentRequest = MMGetNewPvt;
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSURL *url = [NSURL URLWithString:@"http://meemi.com/api3/p/private"];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

-(void)getMemePrivateSent
{
	NSAssert([Meemi isValid], @"getMemePrivateSent: called without valid session");
	self.currentRequest = MMGetNewPvtSent;
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSURL *url = [NSURL URLWithString:@"http://meemi.com/api3/p/private_sent"];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

-(void)getNewMentions
{
	NSAssert([Meemi isValid], @"getNewMentions: called without valid session");
	self.currentRequest = MMGetNewMentions;
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSURL *url = [NSURL URLWithString:@"http://meemi.com/api3/p/only_new_mentions"];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

-(void)getNewPersonalReplies
{ 
	NSAssert([Meemi isValid], @"getNewPersonalReplies: called without valid session");
	self.currentRequest = MMGetNewPersonalReplies;
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSURL *url = [NSURL URLWithString:@"http://meemi.com/api3/p/only_new_replies"];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

-(void)getNewPersonals
{ 
	NSAssert([Meemi isValid], @"getNewPersonals: called without valid session");
	self.currentRequest = MMGetNewPersonals;
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://meemi.com/api3/%@/limit_%d", [Meemi screenName], pageSize]];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

-(void)getNewFavorites
{ 
	NSAssert([Meemi isValid], @"getNewFavorites: called without valid session");
	self.currentRequest = MMGetNewFavorites;
	if(newUsersQueue == nil)
		newUsersQueue = [[NSMutableArray alloc] initWithCapacity:10];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://meemi.com/api3/%@/favourites/limit_%d", [Meemi screenName], pageSize]];
	DLog(@"Now calling %@", url);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	[self startRequestToMeemi:request];	
}

+(void)markMemeSpecial:(NSNumber *)memeID
{
	DLog(@"Now in markMemeSpecial to mark meme %@", memeID);
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for an User with this screen_name.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id == %@", memeID];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		Meme *theOne = [fetchResults objectAtIndex:0];
		theOne.special = [NSNumber numberWithBool:YES];
		if (![managedObjectContext save:&error])
		{
			DLog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					DLog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				DLog(@"  %@", [error userInfo]);
		}
	}
	[request release];
}	

+(void)toggleMemeSpecial:(NSNumber *)memeID
{
	DLog(@"Now in toggleMemeSpecial to toggle meme %@", memeID);
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for an User with this screen_name.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id == %@", memeID];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		Meme *theOne = [fetchResults objectAtIndex:0];
		theOne.special = [NSNumber numberWithBool:(![theOne.special boolValue])];;
		if (![managedObjectContext save:&error])
		{
			DLog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					DLog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				DLog(@"  %@", [error userInfo]);
		}
	}
	[request release];
}	

+(void)toggleMemeReshare:(NSNumber *)memeID screenName:(NSString *)screenName
{
	DLog(@"Now in markMemeRead");
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for a meme with this id.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id == %@", memeID];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		NSString *urlString;
		Meme *theOne = [fetchResults objectAtIndex:0];
		if([theOne.is_reshare boolValue])
		{
			urlString = [NSString stringWithFormat:@"http://meemi.com/api3/p/unreshare/%@/%@", screenName, memeID];
			theOne.is_reshare = [NSNumber numberWithBool:NO];
		}
		else
		{
			urlString = [NSString stringWithFormat:@"http://meemi.com/api3/p/reshare/%@/%@", screenName, memeID];
			theOne.is_reshare = [NSNumber numberWithBool:YES];
		}
		if (![managedObjectContext save:&error])
		{
			DLog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					DLog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				DLog(@"  %@", [error userInfo]);
		}
		NSURL *url = [NSURL URLWithString:urlString];
		DLog(@"In toggleMemeReshare. Sending %@", urlString);
		ASIFormDataRequest *netRequest = [ASIFormDataRequest requestWithURL:url];
		// build the password using SHA-256
		unsigned char hashedChars[32];
		CC_SHA256([[Meemi password] UTF8String],
				  [[Meemi password] lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 
				  hashedChars);
		NSString *hashedData = [[NSData dataWithBytes:hashedChars length:32] description];
		hashedData = [hashedData stringByReplacingOccurrencesOfString:@" " withString:@""];
		hashedData = [hashedData stringByReplacingOccurrencesOfString:@"<" withString:@""];
		hashedData = [hashedData stringByReplacingOccurrencesOfString:@">" withString:@""];	
		[netRequest setPostValue:[Meemi screenName] forKey:@"meemi_id"];
		[netRequest setPostValue:hashedData forKey:@"pwd"];
		[netRequest setPostValue:kAPIKey forKey:@"app_key"];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
		if([netRequest respondsToSelector:@selector(setShouldContinueWhenAppEntersBackground)])	
			[netRequest setShouldContinueWhenAppEntersBackground:YES];
#endif
		[netRequest setDelegate:self];
		[netRequest setDidFinishSelector:@selector(returnOKFromRequestReturningStatus:)];
		[netRequest setDidFailSelector:@selector(returnFailedFromRequestReturningStatus:)];
		[netRequest startAsynchronous];			
	}	
	[request release];
}

+(void)toggleMemeFavorite:(NSNumber *)memeID
{
	DLog(@"Now in toggleMemeFavorite");
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for a meme with this id.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id == %@", memeID];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		Meme *theOne = [fetchResults objectAtIndex:0];
		theOne.is_favorite = [NSNumber numberWithBool:(![theOne.is_favorite boolValue])];
		if (![managedObjectContext save:&error])
		{
			DLog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					DLog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				DLog(@"  %@", [error userInfo]);
		}
		NSString *urlString = [NSString stringWithFormat:@"http://meemi.com/api3/p/fav/%@/%@", theOne.screen_name, theOne.id];
		NSURL *url = [NSURL URLWithString:urlString];
		DLog(@"In toggleMemeFavorite. Sending %@", urlString);
		ASIFormDataRequest *netRequest = [ASIFormDataRequest requestWithURL:url];
		// build the password using SHA-256
		unsigned char hashedChars[32];
		CC_SHA256([[Meemi password] UTF8String],
				  [[Meemi password] lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 
				  hashedChars);
		NSString *hashedData = [[NSData dataWithBytes:hashedChars length:32] description];
		hashedData = [hashedData stringByReplacingOccurrencesOfString:@" " withString:@""];
		hashedData = [hashedData stringByReplacingOccurrencesOfString:@"<" withString:@""];
		hashedData = [hashedData stringByReplacingOccurrencesOfString:@">" withString:@""];	
		[netRequest setPostValue:[Meemi screenName] forKey:@"meemi_id"];
		[netRequest setPostValue:hashedData forKey:@"pwd"];
		[netRequest setPostValue:kAPIKey forKey:@"app_key"];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
		if([netRequest respondsToSelector:@selector(setShouldContinueWhenAppEntersBackground)])	
			[netRequest setShouldContinueWhenAppEntersBackground:YES];
#endif
		[netRequest setDelegate:self];
		[netRequest setDidFinishSelector:@selector(returnOKFromRequestReturningStatus:)];
		[netRequest setDidFailSelector:@selector(returnFailedFromRequestReturningStatus:)];
		[netRequest startAsynchronous];			
	}
	else {
		ALog(@"Meme %@ not found! :-O", memeID);
	}

	[request release];
}

+(void)reallyMarkRead:(NSString *)nilOrCommaSeparatedMemeList
{
	NSString *urlString;
	// If we have to mark all...
	if(nilOrCommaSeparatedMemeList == nil)
		urlString = [NSString stringWithString:@"http://meemi.com/api3/p/mark/all_memes"];
	else
		urlString = [NSString stringWithFormat:@"http://meemi.com/api3/p/mark/multi_meme/%@", nilOrCommaSeparatedMemeList];
		NSURL *url = [NSURL URLWithString:urlString];
	DLog(@"In reallyMarkRead. Sending %@", urlString);
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	// build the password using SHA-256
	unsigned char hashedChars[32];
	CC_SHA256([[Meemi password] UTF8String],
			  [[Meemi password] lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 
			  hashedChars);
	NSString *hashedData = [[NSData dataWithBytes:hashedChars length:32] description];
    hashedData = [hashedData stringByReplacingOccurrencesOfString:@" " withString:@""];
    hashedData = [hashedData stringByReplacingOccurrencesOfString:@"<" withString:@""];
    hashedData = [hashedData stringByReplacingOccurrencesOfString:@">" withString:@""];	
	[request setPostValue:[Meemi screenName] forKey:@"meemi_id"];
	[request setPostValue:hashedData forKey:@"pwd"];
	[request setPostValue:kAPIKey forKey:@"app_key"];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
	if([request respondsToSelector:@selector(setShouldContinueWhenAppEntersBackground)])	
		[request setShouldContinueWhenAppEntersBackground:YES];
#endif
	[request setDelegate:self];
	[request setDidFinishSelector:@selector(returnOKFromRequestReturningStatus:)];
	[request setDidFailSelector:@selector(returnFailedFromRequestReturningStatus:)];
	[request startAsynchronous];			
}

+(void)markMemeRead:(NSNumber *)memeID
{
	DLog(@"Now in markMemeRead");
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for a meme with this id.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id == %@", memeID];
	[request setPredicate:predicate];
	// We're only looking for one.
	[request setFetchLimit:1];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		Meme *theOne = [fetchResults objectAtIndex:0];
		theOne.new_meme = [NSNumber numberWithBool:NO];
		theOne.new_replies = [NSNumber numberWithBool:NO];
		if (![managedObjectContext save:&error])
		{
			DLog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					DLog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				DLog(@"  %@", [error userInfo]);
		}
	}
	[request release];
	NSString *param = [NSString stringWithFormat:@"%@", memeID];
	[self reallyMarkRead:param];
}

+(void)markThreadRead:(NSNumber *)memeID
{
	NSAssert([Meemi isValid], @"markThreadRead: called without valid session");
	NSMutableString *param = [[NSMutableString alloc] initWithCapacity:30];
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for all the new ones.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"reply_id == %@ AND (new_meme == %@ OR new_replies == %@)", 
							  memeID, [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES]];
	[request setPredicate:predicate];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	DLog(@"Got %d new replies to mark read", [fetchResults count]);
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		for(Meme *theOne in fetchResults)
		{
			theOne.new_meme = [NSNumber numberWithBool:NO];
			theOne.new_replies = [NSNumber numberWithBool:NO];
			[param appendFormat:@"%@,", theOne.id];
		}
		// cut the last ','
		if([param length] > 0)
			[param replaceCharactersInRange:NSMakeRange([param length]-1, 1) withString:@""];
		// now commit.
		if (![managedObjectContext save:&error])
		{
			DLog(@"Failed to save to data store: %@", [error localizedDescription]);
			NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
			if(detailedErrors != nil && [detailedErrors count] > 0) 
				for(NSError* detailedError in detailedErrors) 
					DLog(@"  DetailedError: %@", [detailedError userInfo]);
			else 
				DLog(@"  %@", [error userInfo]);
		}
		[self reallyMarkRead:param];
	}
	[param release];
	[request release];
}

+(void)markNewMemesRead
{
	NSAssert([Meemi isValid], @"markNewMemesRead: called without valid session");
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for all the new ones.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"new_meme == %@ OR new_replies == %@", 
							  [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES]];
	[request setPredicate:predicate];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	ALog(@"Got %d new memes to mark read", [fetchResults count]);
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		for(Meme *theOne in fetchResults)
		{
			theOne.new_meme = [NSNumber numberWithBool:NO];
			theOne.new_replies = [NSNumber numberWithBool:NO];
		}
	}	
	[request release];
	// now commit.
	if (![managedObjectContext save:&error])
	{
		DLog(@"Failed to save to data store: %@", [error localizedDescription]);
		NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
		if(detailedErrors != nil && [detailedErrors count] > 0) 
			for(NSError* detailedError in detailedErrors) 
				DLog(@"  DetailedError: %@", [detailedError userInfo]);
		else 
			DLog(@"  %@", [error userInfo]);
	}
	[self reallyMarkRead:nil];
}

+(void)purgeOldMemes
{
	NSAssert([Meemi isValid], @"purgeOldMemes: called without valid session");
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	// We're looking for all the new ones.
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	NSTimeInterval normalDaysBefore = -7.0 * 24.0 * 60.0 * 60.0;	// 7 days in seconds: 432.000 seconds
	NSTimeInterval specialDaysBefore = 50.0 * normalDaysBefore;		// 350 days for "specials"
	NSDate *normalDate = [NSDate dateWithTimeIntervalSinceNow:normalDaysBefore];
	NSDate *specialDate = [NSDate dateWithTimeIntervalSinceNow:specialDaysBefore];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(dt_last_movement < %@ AND special == NO AND private_meme = NO) OR (dt_last_movement < %@)", normalDate, specialDate];
	DLog(@"predicate is: %@", predicate);
	[request setPredicate:predicate];
	NSError *error;
	NSArray *fetchResults = [managedObjectContext executeFetchRequest:request error:&error];
	DLog(@"Got %d new memes to delete because old", [fetchResults count]);
	if (fetchResults != nil && [fetchResults count] != 0)
	{
		for(Meme *theOne in fetchResults)
		{
			DLog(@"Deleting meme %@", theOne.id);
			[managedObjectContext deleteObject:theOne];
		}
	}	
	// now commit.
	if (![managedObjectContext save:&error])
	{
		DLog(@"Failed to save to data store: %@", [error localizedDescription]);
		NSArray* detailedErrors = [[error userInfo] objectForKey:NSDetailedErrorsKey];
		if(detailedErrors != nil && [detailedErrors count] > 0) 
			for(NSError* detailedError in detailedErrors) 
				DLog(@"  DetailedError: %@", [detailedError userInfo]);
		else 
			DLog(@"  %@", [error userInfo]);
	}	
	[request release];
}

-(void)postSomething:(NSString *)withDescription withLocalization:(BOOL)canBeLocalized andOptionalArg:(id)whatever 
			replyWho:(NSString *)replyScreenName replyNo:(NSNumber *)replyID privateTo:(NSString *)privateTo
{
	// accomodate different URLs for save and reply actions
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://meemi.com/api/%@/%@", [Meemi screenName],
									   (replyScreenName == nil) ? @"save" : @"reply"]];
	ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
	if(self.currentRequest == MmRPostImage)
	{
		[request setPostValue:@"image" forKey:@"meme_type"];
		[request setPostValue:@"PC" forKey:@"flag"];
		NSData *imageAsJPEG = UIImageJPEGRepresentation((UIImage *)whatever, 0.75);
		[request setData:imageAsJPEG withFileName:@"unuseful.jpg" andContentType:@"image/jpeg" forKey:@"img_pc"];
	}
	else // this is MmRPostText
	{
		[request setPostValue:@"text" forKey:@"meme_type"];
		[request setPostValue:(NSString *)whatever forKey:@"channels"];
	}
	// If this is a reply
	if(replyScreenName != nil)
	{
		[request setPostValue:replyScreenName forKey:@"reply_screen_name"];
		NSString *temp = [NSString stringWithFormat:@"%@", replyID];
		[request setPostValue:temp forKey:@"reply_meme_id"];
	}
	// If this is a private meme
	if(privateTo != nil)
		[request setPostValue:privateTo forKey:@"private_sn"];
	// Localization
	if(!canBeLocalized) 
		[request setPostValue:NSLocalizedString(@"An unknown place", @"") forKey:@"location"];
	else
		[request setPostValue:[Meemi nearbyPlaceName] forKey:@"location"];
	[request setPostValue:withDescription forKey:@"text_content"];
	[self startRequestToMeemi:request];
	// If it's a reply, mark the parent meme as "special"
	if(replyScreenName != nil)
		[Meemi markMemeSpecial:replyID];
}

-(void)postImageAsMeme:(UIImage *)image withDescription:(NSString *)description withLocalization:(BOOL)canBeLocalized
{
	// Sanity checks
	NSAssert([Meemi isValid], @"postImageAsMeme:withDescription called without valid session");
	// Set current request type
	self.currentRequest = MmRPostImage;
	[self postSomething:description withLocalization:canBeLocalized andOptionalArg:image replyWho:nil replyNo:nil privateTo:nil];
}

-(void)postImageAsReply:(UIImage *)image withDescription:(NSString *)description withLocalization:(BOOL)canBeLocalized 
			   replyWho:(NSString *)replyScreenName replyNo:(NSNumber *)replyID;
{
	// Sanity checks
	NSAssert([Meemi isValid], @"postImageAsReply:withDescription called without valid session");
	// Set current request type
	self.currentRequest = MmRPostImage;
	[self postSomething:description withLocalization:canBeLocalized andOptionalArg:image replyWho:replyScreenName replyNo:replyID privateTo:nil];
}

-(void)postTextAsMeme:(NSString *)description withChannel:(NSString *)channel withLocalization:(BOOL)canBeLocalized
{
	// Sanity checks
	NSAssert([Meemi isValid], @"postTextAsMeme:withDescription called without valid session");
	// Set current request type
	self.currentRequest = MmRPostText;
	[self postSomething:description withLocalization:canBeLocalized andOptionalArg:channel replyWho:nil replyNo:nil privateTo:nil];
}

-(void)postTextReply:(NSString *)description withChannel:(NSString *)channel withLocalization:(BOOL)canBeLocalized 
			replyWho:(NSString *)replyScreenName replyNo:(NSNumber *)replyID
{
	// Sanity checks
	NSAssert([Meemi isValid], @"postTextAsReply:withDescription called without valid session");
	// Set current request type
	self.currentRequest = MmRPostText;
	[self postSomething:description withLocalization:canBeLocalized andOptionalArg:channel replyWho:replyScreenName replyNo:replyID privateTo:nil];
}

-(void)postTextAsPrivateMeme:(NSString *)description withChannel:(NSString *)channel withLocalization:(BOOL)canBeLocalized privateTo:(NSString *)privateTo
{
	// Sanity checks
	NSAssert([Meemi isValid], @"postTextAsPrivateMeme: called without valid session");
	// Set current request type
	self.currentRequest = MmRPostText;
	[self postSomething:description withLocalization:canBeLocalized andOptionalArg:channel replyWho:nil replyNo:nil privateTo:privateTo];
}

#pragma mark CLLocationManagerDelegate and its delegate

- (void)stopLocation
{
	if(locationManager)
		[locationManager stopUpdatingLocation];
}

- (void)startLocation
{
	// If user already deny once this session, bail out
	if(self.isLCDenied)
		return;
	// if user denied thrice, bail out...
	if(self.nLocationUseDenies >= 3)
		return;
    // Create the location manager if this object does not
    // already have one.
    if (nil == locationManager)
        locationManager = [[CLLocationManager alloc] init];
	
	locationManager.delegate = self;
	locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
	
	// Set a movement threshold for new events
	locationManager.distanceFilter = 100;
	
	// We want a full service :)
	needLocation = YES;
	
	[locationManager startUpdatingLocation];	
}


// Delegate method from the CLLocationManagerDelegate protocol.
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
    // If it's a relatively recent event, turn off updates to save power
    NSDate* eventDate = newLocation.timestamp;
    NSTimeInterval howRecent = [eventDate timeIntervalSinceNow];
    if (abs(howRecent) < 5.0)
    {
		// Check accuracy and continue to look if more than 100m...
		if(newLocation.horizontalAccuracy < 101)
		{
			DLog(@"Got a stable position");
			[manager stopUpdatingLocation];
		}
		
		needLocation = NO;
		// init a safe value, if void and if we don't have a reverse location
		if([[Meemi nearbyPlaceName] isEqualToString:@""])
		{
			[Meemi setNearbyPlaceName:[NSString stringWithFormat:@"lat %+.4f, lon %+.4f ±%.0fm",
									newLocation.coordinate.latitude, newLocation.coordinate.longitude, newLocation.horizontalAccuracy]];
			DLog(@"Got a position: lat %+.4f, lon %+.4f ±%.0fm\nPlacename still unknown.",
				 newLocation.coordinate.latitude, newLocation.coordinate.longitude, newLocation.horizontalAccuracy);
		}
        // Set the new position, in case we already have a reverse geolocation, but we have a new position
		if(self.placeName != nil && self.state != nil)
		{
			[Meemi setNearbyPlaceName:[NSString stringWithFormat:@"%@, %@ (lat %+.4f, lon %+.4f ±%.0fm)",
									[self.placeName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
									[self.state stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
									locationManager.location.coordinate.latitude, locationManager.location.coordinate.longitude, 
									locationManager.location.horizontalAccuracy]];
			DLog(@"Got a new position (reverse geoloc already in place): %@", [Meemi nearbyPlaceName]);
		}
			
		// Notify the world that we have found ourselves
		[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kGotLocation object:self]];
		// Look for reverse geolocation (only if query is not pending)
        if(!theReverseGeocoder.isQuerying)
        {
            DLog(@"Starting reverse geolocation query");
            if(theReverseGeocoder == nil)
                theReverseGeocoder = [[MKReverseGeocoder alloc] initWithCoordinate:newLocation.coordinate];
            else
                [theReverseGeocoder initWithCoordinate:newLocation.coordinate];
            theReverseGeocoder.delegate = self;
            [theReverseGeocoder start];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
	// if the user don't want to give us the rights, give up.
	if(error.code == kCLErrorDenied)
	{
		[manager stopUpdatingLocation];
		// mark that user already denied us for this session
		self.lcDenied = YES;
		// add one to Get how many times user refused and save to default
		self.nLocationUseDenies = self.nLocationUseDenies + 1;
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setInteger:self.nLocationUseDenies forKey:@"userDeny"];
	}
}

#pragma mark NSReverseGeocoderDelegate

- (void)reverseGeocoder:(MKReverseGeocoder *)geocoder didFailWithError:(NSError *)error
{
    ALog(@"Reverse geolocation failed with error: '%@'", [error localizedDescription]);
}

- (void)reverseGeocoder:(MKReverseGeocoder *)geocoder didFindPlacemark:(MKPlacemark *)placemark
{
    DLog(@"Got a placemark!");
    DLog(@"thoroughfare: %@", placemark.thoroughfare);
    DLog(@"subThoroughfare: %@", placemark.subThoroughfare);
    DLog(@"postalCode: %@", placemark.postalCode);
    DLog(@"subLocality: %@", placemark.subLocality);
    DLog(@"locality: %@", placemark.locality);
    DLog(@"subAdministrativeArea: %@", placemark.subAdministrativeArea);
    DLog(@"administrativeArea: %@", placemark.administrativeArea);
    DLog(@"country: %@", placemark.country);
    self.placeName = [NSString stringWithFormat:@"%@", placemark.locality];
    self.state = [NSString stringWithFormat:@"%@, %@", placemark.administrativeArea, placemark.country];
    [Meemi setNearbyPlaceName:[NSString stringWithFormat:@"%@, %@ (lat %+.4f, lon %+.4f ±%.0fm)",
                               self.placeName, self.state,
                               locationManager.location.coordinate.latitude, locationManager.location.coordinate.longitude, 
                               locationManager.location.horizontalAccuracy]];
    ALog(@"Got a full localization: %@", [Meemi nearbyPlaceName]);
    // Notify the world that we have found ourselves
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kGotLocation object:self]];
    [theReverseGeocoder release];
    theReverseGeocoder = nil;
}

@end
