//
//  WithFriendsController.m
//  Meemi
//
//  Created by Giacomo Tufano on 02/04/10.
//
//  Copyright 2011, Giacomo Tufano (gt@ilTofa.it)
//  Licensed under MIT license. See LICENSE file or http://www.opensource.org/licenses/mit-license.php
//

#import "WithFriendsController.h"
#import "MeemiAppDelegate.h"
#import "Meme.h"
#import "MemeOnWeb.h"
#import "UserProfile.h"
#import "UserDetail.h"
#import "SettingsController.h"

#import <QuartzCore/QuartzCore.h>
#import "RegexKitLite.h"

@implementation WithFriendsController

@synthesize memeCell, predicateString, replyTo, replyScreenName, replyQuantity;
@synthesize headerView, headerLabel, headerArrow, laRuota, laPiccolaRuota, reloadButtonInBreakTable;
@synthesize searchString, searchScope, theSearchBar;

-(void)setWatermark:(int)numberRead
{
	DLog(@"setWatermark: called with %d", numberRead);
	if(currentFetch == FTReplyView)
	{
		readMemes += numberRead;
		// In case of reply, if 20 read (a full page), and we're still not read all...
		// set the watermark to the first (because we're reading it backwards)
		if(numberRead == 20 && readMemes < [self.replyQuantity intValue])
			watermark = 1;
		else
			watermark = INT_MAX;
	}
	else
		watermark = numberRead;
}

-(int)watermark
{
	return watermark;
}

-(void)deviceShaken:(NSNotification *)note
{
	DLog(@"SHAKED!");
	// Ask if mark read (only if not in a detail view).
	if(self.replyTo == nil)
		[self markReadMemes];
}

-(IBAction)loadMore:(id)sender
{
	DLog(@"loadMore: clicked");
	if(!ourPersonalMeemi)
	{
		ALog(@"*** Abnormal condition: loadMore: called without a valid ourPersonalMeemi. Reverting to a standard reload");
		ourPersonalMeemi = [[Meemi alloc] initFromUserDefault];
		if(!ourPersonalMeemi)
			ALog(@"Meemi session init failed. Shit...");
	}
	ourPersonalMeemi.delegate = self;
	if(currentFetch == FTReplyView)
		[ourPersonalMeemi getMemeRepliesOf:self.replyTo screenName:self.replyScreenName total:[self.replyQuantity intValue]];
	else
		[ourPersonalMeemi getMemes];
}

-(void)meemiIsBusy:(NSNotification *)note
{
	DLog(@"meemiIsBusy:");
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.4];
	self.tableView.contentInset = UIEdgeInsetsMake(60.0f, 0.0f, 0.0f, 0.0f);
	self.headerLabel.text = NSLocalizedString(@"Reloading...", @"");
	self.headerArrow.text = @" ";
	[UIView commitAnimations];	
	[self.laRuota startAnimating];
	[self.reloadButtonInBreakTable setImage:[UIImage imageNamed:@"Nothing"]
								   forState:UIControlStateNormal];
	[self.laPiccolaRuota startAnimating];
}

-(void)meemiIsFree:(NSNotification *)note
{
	DLog(@"meemiIsFree:");
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.4];
	self.tableView.contentInset = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f);
	[UIView commitAnimations];	
	[self.laRuota stopAnimating];
	[self.laPiccolaRuota stopAnimating];
	[self.reloadButtonInBreakTable setImage:[UIImage imageNamed:@"02-redo"]
								   forState:UIControlStateNormal];
	self.headerLabel.text = NSLocalizedString(@"Pull down to Reload", @"");
	self.headerArrow.text = @"☟";
	[self.tableView reloadData];
}

-(void)resetHeader
{
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.4];
	self.tableView.contentInset = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f);
	[UIView commitAnimations];	
	[self.laRuota stopAnimating];
	[self.laPiccolaRuota stopAnimating];
	[self.reloadButtonInBreakTable setImage:[UIImage imageNamed:@"02-redo"]
								   forState:UIControlStateNormal];
	self.headerLabel.text = NSLocalizedString(@"Pull down to Reload", @"");
	self.headerArrow.text = @"☟";
}

-(void)mergeNewData:(NSNotification *)note
{
	DLog(@"Calling mergeChangesFromContextDidSaveNotification: on Meemi context");
	[[Meemi managedObjectContext] mergeChangesFromContextDidSaveNotification:note];
}

-(void)settingsView
{
	SettingsController *controller = [[SettingsController alloc] initWithNibName:@"SettingsController" bundle:nil];
	[self.navigationController pushViewController:controller animated:YES];
	[controller release];
	controller = nil;	
}

-(IBAction)avatarTouched:(id)sender
{
	DLog(@"avatarTouched at row: %d", [[((UIButton *)sender) titleForState:UIControlStateNormal] integerValue]);
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[[((UIButton *)sender) titleForState:UIControlStateNormal] integerValue] 
												inSection:0];
	if(indexPath)
	{
		Meme *theFetchedMeme = [theMemeList objectAtIndexPath:indexPath];
		if(theFetchedMeme)
		{
			// Push user detail view
			UserProfile *detailViewController = [[UserProfile alloc] initWithNibName:@"UserProfile" bundle:nil];
			detailViewController.theUser = theFetchedMeme.user;
			// Pass the selected object to the new view controller.
			[self.navigationController pushViewController:detailViewController animated:YES];
			[detailViewController release];		
		}
	}
}

-(void)loadUserList
{
	UserDetail *userListController = [[UserDetail alloc] initWithNibName:@"UserDetail" bundle:nil];
	[self.navigationController pushViewController:userListController animated:YES];
	[userListController release];
}

-(IBAction)doNothing:(id)sender
{
}

-(IBAction)toggleSpecial:(id)sender
{
	// Get the first meme
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
	Meme *selectedMeme = ((Meme *)[theMemeList objectAtIndexPath:indexPath]);
	// and toggle the Special flag on it (marking the thread as "not special" anymore if needed)... :)
	specialThread = ![selectedMeme.special boolValue];
	[Meemi toggleMemeSpecial:selectedMeme.id];
}

-(IBAction)toggleReshare:(id)sender
{
	// Get the first meme
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
	Meme *selectedMeme = ((Meme *)[theMemeList objectAtIndexPath:indexPath]);
	// and toggle the Special flag on it (marking the thread as "not special" anymore if needed)... :)
	specialThread = ![selectedMeme.is_reshare boolValue];
	[Meemi toggleMemeReshare:selectedMeme.id screenName:selectedMeme.screen_name];
}

-(IBAction)toggleFavorite:(id)sender
{
	// Get the first meme
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
	Meme *selectedMeme = ((Meme *)[theMemeList objectAtIndexPath:indexPath]);
	// and toggle the Special flag on it (marking the thread as "not special" anymore if needed)... :)
	DLog(@"toggleFavorite: Meme is: %@, currently favorite is %@", selectedMeme, selectedMeme.is_favorite);
	if([selectedMeme.is_favorite boolValue])
	{
		// This will reset the favorite status
		specialThread = NO;
	}
	else 
	{
		specialThread = YES;
	}
	[Meemi toggleMemeFavorite:selectedMeme.id];
}

-(void)setupFetch
{
	NSManagedObjectContext *context = [Meemi managedObjectContext];
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	// Configure the request's entity, and optionally its predicate.
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"Meme" inManagedObjectContext:context];
	[fetchRequest setEntity:entityDescription];
	NSSortDescriptor *sortDescriptor;
	if(currentFetch == FTReplyView)
		sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"date_time" ascending:YES];
	else
		sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"dt_last_movement" ascending:NO];		
	NSArray *sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
	[fetchRequest setSortDescriptors:sortDescriptors];
	switch(currentFetch)
	{
		case FTAll:
			self.predicateString = @"reply_id == 0 AND private_meme == NO";
			break;
		case FTPvt:
			self.predicateString = [NSString stringWithFormat:@"private_meme == YES AND reply_id == 0"];
			break;
		case FTSpecial:
			self.predicateString = [NSString stringWithFormat:@"private_meme == NO AND special == YES and reply_id == 0"];
			break;
		case FTReplyView:
			self.predicateString = [NSString stringWithFormat:@"reply_id == %@ OR id == %@", self.replyTo, self.replyTo];
			break;
	}
	
	// Get (and add) search parameters if we have a search running
	if(![self.searchString isEqualToString:@""])
	{
		NSString *tempString = nil;
		if(self.searchScope == 0)
		{
			DLog(@"searching on sender");
			tempString = [NSString stringWithFormat:@"%@ AND user.screen_name like[c] \"%@*\"", self.predicateString, self.searchString];
		}
		if(self.searchScope == 1)
		{
			DLog(@"searching on text");
			tempString = [NSString stringWithFormat:@"%@ AND content like[c] \"*%@*\"", self.predicateString, self.searchString];
		}
		if(self.searchScope == 2)
		{
			DLog(@"searching on channel");
			tempString = [NSString stringWithFormat:@"%@ AND channels like[c] \"%@*\"", self.predicateString, self.searchString];
		}
		self.predicateString = tempString;
	}

	DLog(@"In setupFetch. Type of fetch: %d. Filter: %@", currentFetch, self.predicateString);
	if(![self.predicateString isEqualToString:@""])
	{
		NSPredicate *predicate = [NSPredicate predicateWithFormat:self.predicateString];
		[fetchRequest setPredicate:predicate];
	}
	[sortDescriptors release];
	[sortDescriptor release];
	
	if(theMemeList != nil)
	{
		theMemeList.delegate = nil;
		[theMemeList release];
		theMemeList = nil;
	}
	if(currentFetch == FTReplyView)
	{
		[NSFetchedResultsController deleteCacheWithName:@"ThreadCache"];
		theMemeList = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest 
														  managedObjectContext:context 
															sectionNameKeyPath:nil 
																	 cacheName:@"ThreadCache"];
	}
	else
	{
		[NSFetchedResultsController deleteCacheWithName:@"WithFriendsCache"];
		theMemeList = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest 
														  managedObjectContext:context 
															sectionNameKeyPath:nil 
																	 cacheName:@"WithFriendsCache"];
	}
	[fetchRequest release];
	theMemeList.delegate = self;
	
	NSError *error;
	if(![theMemeList performFetch:&error])
	{
		NSLog(@"Error in performFetch: %@", error);
		UIAlertView *theAlert = [[[UIAlertView alloc] initWithTitle:@"Error"
															message:[error localizedDescription]
														   delegate:nil
												  cancelButtonTitle:@"OK" 
												  otherButtonTitles:nil] 
								 autorelease];
		[theAlert show];
	}
	[self.tableView reloadData];
	
	// If we're selecting the "private" or the "special" view, it's time to reload
	// Alloc a new Meemi for that, and release it on return
	if(currentFetch == FTPvt)
	{
		// Setup the Meemi "agent"
		// If already existing, a query is still running, leave it alone
		if(privateFetchMeemi == nil)
		{
			privateFetchMeemi = [[Meemi alloc] initFromUserDefault];
			if(!privateFetchMeemi)
				ALog(@"Meemi privateFetch session init failed. Shit...");
			else
			{
				privateFetchMeemi.delegate = self;
				[privateFetchMeemi getMemePrivateReceived];
			}
		}
	}
	if(currentFetch == FTSpecial)
	{
		// Setup the Meemi "agent"
		// If already existing, a query is still running, leave it alone
		if(mentionFetchMeemi == nil)
		{
			mentionFetchMeemi = [[Meemi alloc] initFromUserDefault];
			if(!mentionFetchMeemi)
				ALog(@"Meemi mentionFetch session init failed. Shit...");
			else
			{
				mentionFetchMeemi.delegate = self;
				[mentionFetchMeemi getNewMentions];
			}
		}
	}	
}	

-(void)filterSelected
{
	currentFetch = ((UISegmentedControl *) (((UIBarButtonItem *)[self.toolbarItems objectAtIndex:2]).customView)).selectedSegmentIndex;
	DLog(@"in filterSelected for %d selected, filtering on '%@'", currentFetch, self.searchString);
	[self setupFetch];
}

-(void)loadMemePage
{
	DLog(@"loadMemePage called");
	if(![Meemi isValid])
	{
		ALog(@"loadMemePage called with invalid session, abort loading");
		return;
	}
	// reset nextPageToLoad, we want a complete retry
	ourPersonalMeemi.nextPageToLoad = 1;
	ourPersonalMeemi.delegate = self;
	if(self.replyTo != nil) // Reload the "private" page
		[ourPersonalMeemi getMemeRepliesOf:self.replyTo screenName:self.replyScreenName total:[self.replyQuantity intValue]];
	else 
    {
        // Reload the "personal" pages...
        if(currentFetch == FTSpecial)
        {
            // Setup the Meemi "agent"
            // If already existing, a query is still running, leave it alone
            if(mentionFetchMeemi == nil)
            {
                mentionFetchMeemi = [[Meemi alloc] initFromUserDefault];
                if(!mentionFetchMeemi)
                    ALog(@"Meemi mentionFetch session init failed. Shit...");
                else
                {
                    mentionFetchMeemi.delegate = self;
                    [mentionFetchMeemi getNewMentions];
                }
            }
        }
        else // "normal" reload
            [ourPersonalMeemi getMemes];
    }
}

-(void)markReadMemes
{
	thatsTheMemeKindChoice = NO;
	UIActionSheet *chooseIt = [[[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Mark Memes Read?", @"")
														   delegate:self 
												  cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
											 destructiveButtonTitle:NSLocalizedString(@"Mark", @"")
												  otherButtonTitles:nil]
							   autorelease];
	[chooseIt showFromToolbar:self.navigationController.toolbar];
}

#pragma mark MeemiDelegate

-(void)meemi:(MeemiRequest)request didFailWithError:(NSError *)error
{
	// if error == nil we, probably, are called because of a wrong username
	DLog(@"in WithFriendsCOnrtoller didFailWithError. Error is %@", error);
	if(error != nil)
	{
		NSString *theMessage = [NSString stringWithFormat:NSLocalizedString(@"Error loading data: %@. Please try again later", @""),
								[error localizedDescription]];
		UIAlertView *theAlert = [[[UIAlertView alloc] initWithTitle:@"Error"
															message:theMessage
														   delegate:nil
												  cancelButtonTitle:@"OK" 
												  otherButtonTitles:nil] 
								 autorelease];
		[theAlert show];
	}
	// release special meemi
	if(request == MMGetNewPvt || request == MMGetNewPvtSent)
	{
		privateFetchMeemi.delegate = nil;
		[privateFetchMeemi release];
		privateFetchMeemi = nil;
	} 
    // That's the "personal list sequence"
	if(request == MMGetNewMentions)
	{
		// Get new private replies
		[mentionFetchMeemi getNewPersonalReplies];
	}
	if(request == MMGetNewPersonalReplies)
    {
        // Get new "personal"
        [mentionFetchMeemi getNewPersonals];
    }
	if(request == MMGetNewPersonals)
    {
        // Get new "favourites"
        [mentionFetchMeemi getNewFavorites];
    }
    if(request == MMGetNewFavorites)
	{
		mentionFetchMeemi.delegate = nil;
		[mentionFetchMeemi release];
		mentionFetchMeemi = nil;
	}
}	

-(void)meemi:(MeemiRequest)request didFinishWithResult:(MeemiResult)result
{
	// If returning from "get new replies", get avatars if needed.
	if(request == MMGetNewReplies)
	{
		DLog(@"got replies");
	}
	// If pvt received, call pvtSent...
	if(request == MMGetNewPvt)
		[privateFetchMeemi getMemePrivateSent];
	// if private sent, kill private Meemi session
	if(request == MMGetNewPvtSent)
	{
		privateFetchMeemi.delegate = nil;
		[privateFetchMeemi release];
		privateFetchMeemi = nil;
	}
    // That's the "personal list sequence"
	if(request == MMGetNewMentions)
	{
		// Get new private replies
		[mentionFetchMeemi getNewPersonalReplies];
	}
	if(request == MMGetNewPersonalReplies)
    {
        // Get new "personal"
        [mentionFetchMeemi getNewPersonals];
    }
	if(request == MMGetNewPersonals)
    {
        // Get new "favourites"
        [mentionFetchMeemi getNewFavorites];
    }
    if(request == MMGetNewFavorites)
	{
		mentionFetchMeemi.delegate = nil;
		[mentionFetchMeemi release];
		mentionFetchMeemi = nil;
	}
}

#pragma mark ImageSenderControllerDelegate & TextSenderControllerDelegate

-(void)doneWithTextSender
{
	self.navigationController.navigationBarHidden = NO;
	[self.navigationController popViewControllerAnimated:YES];
	// reload to get new meme
	[self loadMemePage];
}

-(void)doneWithImageSender
{
	[self doneWithTextSender];
}

#pragma mark Reply and Reload

-(IBAction)replyToMeme:(id)sender
{
	DLog(@"replyToMeme: called");
	// If we are on private messages view (not reply) go on with a private message
	if(currentFetch == FTPvt)
	{
		DLog(@"Send a private meme to ourselves: %@", [Meemi screenName]);
		TextSender *controller = [[TextSender alloc] initWithNibName:@"TextSender" bundle:nil];
		controller.delegate = self;
		controller.recipientNames = [Meemi screenName];
		[self.navigationController pushViewController:controller animated:YES];
		[controller release];
	}
	else
	{
		// Make user choose if (s)he wants to reply with text or image
		thatsTheMemeKindChoice = YES;
        NSString *sheetTitle;
        if(self.replyScreenName == nil)
            sheetTitle = NSLocalizedString(@"Write a meme with?", @"");
        else
            sheetTitle = NSLocalizedString(@"Reply with?", @"");
		UIActionSheet *chooseIt = [[[UIActionSheet alloc] initWithTitle:sheetTitle
															   delegate:self 
													  cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
												 destructiveButtonTitle:nil
													  otherButtonTitles:NSLocalizedString(@"Text", @""), NSLocalizedString(@"Image", @""), nil]
								   autorelease];
		[chooseIt showFromToolbar:self.navigationController.toolbar];
	}
}	

#pragma mark UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if(thatsTheMemeKindChoice)
	{
		NSLog(@"Kind of meme chosen. Clicked button #%d", buttonIndex);
		if(buttonIndex == 0) // Text
		{
			TextSender *controller = [[TextSender alloc] initWithNibName:@"TextSender" bundle:nil];
			controller.delegate = self;
			controller.replyTo = self.replyTo;
			controller.replyScreenName = self.replyScreenName;
			[self.navigationController pushViewController:controller animated:YES];
			[controller release];
		}
		else if(buttonIndex == 1) // Image
		{
			ImageSender *controller = [[ImageSender alloc] initWithNibName:@"ImageSender" bundle:nil];
			controller.delegate = self;
			controller.replyTo = self.replyTo;
			controller.replyScreenName = self.replyScreenName;
			[self.navigationController pushViewController:controller animated:YES];
			[controller release];
		}
	}
	else 
	{
		if(buttonIndex == 1) // cancel
		{
			DLog(@"Mark read cancelled");
		}
		else
		{
			DLog(@"Mark read chosen");
			[((MeemiAppDelegate *)[[UIApplication sharedApplication] delegate]) markReadMemes];
		}
	}

}

#pragma mark Searchbar & delegate

-(void)dismissSearch
{
	self.tableView.tableHeaderView = nil;
	barPresent = NO;
	searchString = @"";
	[self setupFetch];
}

-(IBAction)searchClicked:(id)sender
{
	if(!barPresent)
	{
		[self.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:YES];
		self.tableView.tableHeaderView = self.theSearchBar;
		barPresent = YES;
		[self.theSearchBar becomeFirstResponder];
	}
	else 
	{
		[self dismissSearch];
	}
	
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
	[self dismissSearch];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
	DLog(@"searchBarSearchButtonClicked here");
	DLog(@"text to search: \"%@\"", searchBar.text);
	DLog(@"Scope is %d", searchBar.selectedScopeButtonIndex);
	self.searchString = searchBar.text;
	self.searchScope = searchBar.selectedScopeButtonIndex;
	[searchBar resignFirstResponder];
	[self setupFetch];
}

#pragma mark Standard Stuff

- (void)viewDidLoad 
{
    [super viewDidLoad];

	// Setup the "reload" view
	[[NSBundle mainBundle] loadNibNamed:@"headerView" owner:self options:nil];
	self.headerView.frame = CGRectMake(0.0f, -65.0f, 320.0f, 65.0f);
	self.headerView.hidden = NO;
	[self.view addSubview:self.headerView];
	self.watermark = INT_MAX;
	DLog(@"nib loaded. headerView is now: %@", self.headerView);
	
	// "Cache" the UIImages
	imgCamera = [UIImage imageNamed:@"camera-verysmall"];
	[imgCamera retain];
	imgVideo = [UIImage imageNamed:@"video-verysmall"];
	[imgVideo retain];
	imgLink= [UIImage imageNamed:@"link-verysmall"];
	[imgLink retain];
	imgBlackFlag = [UIImage imageNamed:@"BlackFlag"];
	[imgBlackFlag retain];
	imgWhiteFlag = [UIImage imageNamed:@"WhiteFlag"];
	[imgWhiteFlag retain];
	imgSemplice = [UIImage imageNamed:@"memeSemplice"];
	[imgSemplice retain];
	imgNothing = [UIImage imageNamed:@"Nothing"];
	[imgNothing retain];
	imgLock = [UIImage imageNamed:@"icon-lock2"];
	[imgLock retain];
	imgStar = [UIImage imageNamed:@"star"];
	[imgStar retain];
	
	// Setup the Meemi "agent"
	ourPersonalMeemi = [[Meemi alloc] initFromUserDefault];
	if(!ourPersonalMeemi)
		ALog(@"Meemi session init failed. Shit...");
	ourPersonalMeemi.delegate = self;
	
	self.searchString = @"";
	
	self.parentViewController.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"fondino.png"]];
	self.tableView.backgroundColor = [UIColor clearColor];
	
#define kButtonWidth 55.0f

	if(self.replyTo == nil)
	{
		[self loadMemePage];
		
		// Add a left button for the settings
		UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"20-gear2"] 
																		 style:UIBarButtonItemStylePlain 
																		target:self 
																		action:@selector(settingsView)];
		self.navigationItem.leftBarButtonItem = reloadButton;
		[reloadButton release];
		UIBarButtonItem *readB = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"UsersList"] 
																  style:UIBarButtonItemStylePlain 
																 target:self
																 action:@selector(loadUserList)];
		[readB setWidth:kButtonWidth];
		UIBarButtonItem *srchB = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"magnifying-glass"] 
																  style:UIBarButtonItemStylePlain 
																 target:self 
																 action:@selector(searchClicked:)];
		[srchB setWidth:kButtonWidth];
		UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		NSArray *tempStrings = [NSArray arrayWithObjects:
								[UIImage imageNamed:@"HomeForSegmented"],
								[UIImage imageNamed:@"LockForSegmented"],
								[UIImage imageNamed:@"UserForSegmented"]
								, nil];
		UISegmentedControl *theSegment = [[UISegmentedControl alloc] initWithItems:tempStrings];
		theSegment.segmentedControlStyle = UISegmentedControlStyleBar;        
		theSegment.tintColor = [UIColor colorWithRed:0.70313 green:0.73477 blue:0.75938 alpha:1.0];
		theSegment.momentary = NO;
		theSegment.selectedSegmentIndex = 0;
		for (int i = 0; i < 3; i++)
			[theSegment setWidth:kButtonWidth forSegmentAtIndex:i];
		[theSegment addTarget:self action:@selector(filterSelected) forControlEvents:UIControlEventValueChanged];
		NSArray *toolbarItems = [NSArray arrayWithObjects:
								 srchB,
								 spacer,
								 [[[UIBarButtonItem alloc] initWithCustomView:theSegment] autorelease], 
								 spacer,
								 readB,
								 nil];
		self.toolbarItems = toolbarItems;
		[theSegment release];
		[spacer release];
		[srchB release];
		[readB release];
		currentFetch = FTAll;
		[self setupFetch];
	}
	else
	{
		currentFetch = FTReplyView;
		readMemes = 0;
		self.title = NSLocalizedString(@"Thread", @"");
		[self loadMemePage];
		// Toolbar buttons (only if not private)
#define kThreadButtonWidth 75.0
		UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		UIBarButtonItem *specialB = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"StartForSegmented"] 
																   style:UIBarButtonItemStylePlain 
																  target:self
																  action:@selector(toggleSpecial:)];
		[specialB setWidth:kThreadButtonWidth];
		UIBarButtonItem *favB = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"FavoriteButton"] 
																  style:UIBarButtonItemStylePlain 
																 target:self
																 action:@selector(toggleFavorite:)];
		[favB setWidth:kThreadButtonWidth];
		UIBarButtonItem *shareB = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ReshareButton"] 
																  style:UIBarButtonItemStylePlain 
																 target:self
																 action:@selector(toggleReshare:)];
		[shareB setWidth:kThreadButtonWidth];
		NSArray *toolbarItems = [NSArray arrayWithObjects:specialB, spacer, favB, spacer, shareB, nil];
//		NSArray *toolbarItems = [NSArray arrayWithObjects:specialB, favB, shareB, nil];
		self.toolbarItems = toolbarItems;
		[shareB release];
		[favB release];
		[specialB release];
		[spacer release];
	}
	// hid the search bar...
	self.tableView.tableHeaderView = nil;
	// Show the toolbar
	self.navigationController.toolbarHidden = NO;
	
	// Add a right button for reply to the meme list
	UIBarButtonItem *replyButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose 
																				 target:self 
																				 action:@selector(replyToMeme:)];
	self.navigationItem.rightBarButtonItem = replyButton;
	[replyButton release];
}

- (void)viewWillAppear:(BOOL)animated 
{
    [super viewWillAppear:animated];
	// Show the toolbar
	self.navigationController.toolbarHidden = NO;
	self.navigationController.navigationBarHidden = NO;
	// Add notifications observers
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(meemiIsBusy:) name:kNowBusy object:nil];		
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(meemiIsFree:) name:kNowFree object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadMemePage) name:kNewUser object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mergeNewData:) name:NSManagedObjectContextDidSaveNotification object:nil];
	// And register to be notified for shaking and busy/not busy of Meemi session
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceShaken:) name:@"deviceShaken" object:nil];
	if(self.replyTo == nil)
	{
		// Load settings, if still needed.
		if(![Meemi isValid])
			[self settingsView];		
	}
	else 
	{
		[self setupFetch];
	}
	// If no standard user push settings view
	if(![[NSUserDefaults standardUserDefaults] integerForKey:@"userValidated"])
		[self settingsView];
}

- (void)viewDidAppear:(BOOL)animated 
{
	DLog(@"viewDidAppear");
    [super viewDidAppear:animated];
	specialThread = NO;
	[self resetHeader];
	[self.tableView reloadData];
}


- (void)viewWillDisappear:(BOOL)animated 
{
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	// if this is a specialThread, mark the parent "Special"
	if(specialThread && self.replyTo != nil)
		[Meemi markMemeSpecial:self.replyTo];
	// if this is the detail view, reset fetchcontroller...
	if(self.replyTo != nil && theMemeList != nil)
	{
		theMemeList.delegate = nil;
		[theMemeList release];
		theMemeList = nil;
		// and mark the thread read...
		[Meemi markThreadRead:self.replyTo];
	}
	// It happens that we don't need any callback from Meemi anymore.
	if([Meemi sharedSession].delegate == self)
		[Meemi sharedSession].delegate = nil;
	if(ourPersonalMeemi.delegate == self)
		ourPersonalMeemi.delegate = nil;
}

/*
- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
}
*/

/*
// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
*/

- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload 
{
	// release the "Cache" the UIImages
	[imgCamera release];
	imgCamera = nil;
	[imgVideo release];
	imgVideo = nil;
	[imgLink release];
	imgLink = nil;
	[imgBlackFlag release];
	imgBlackFlag = nil;
	[imgWhiteFlag release];
	imgWhiteFlag = nil;
	[imgNothing release];
	imgNothing = nil;
	[imgSemplice release];
	imgSemplice = nil;
	[imgLock release];
	imgLock = nil;
	[imgStar release];
	imgStar = nil;
	// Release other...
	[self.theSearchBar release];
	self.theSearchBar = nil;
	ourPersonalMeemi.delegate = nil;
	[ourPersonalMeemi release];
	ourPersonalMeemi = nil;
	[theMemeList release];
	theMemeList = nil;
}

#pragma mark NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller 
{
	[self.tableView reloadData];
}

#pragma mark Table view methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView 
{
    return [[theMemeList sections] count];
}


// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
    id <NSFetchedResultsSectionInfo> sectionInfo = [[theMemeList sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

#define kTextWidth 271.0f
#define kHeigthBesideText 85.0f
#define kExtraHeightForReload 50.0f
#define kMaxHeight 150.0f

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    NSString *cellIdentifier;
	
	if((currentFetch == FTAll || currentFetch == FTReplyView) && indexPath.row == (self.watermark - 1))
		cellIdentifier = @"LoadAgainMemeCell";
	else
		cellIdentifier = @"MemeCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
	
    if (cell == nil) 
	{
		[[NSBundle mainBundle] loadNibNamed:cellIdentifier owner:self options:nil];
        cell = memeCell;
        self.memeCell = nil;
    }
    
	Meme *theFetchedMeme = [theMemeList objectAtIndexPath:indexPath];
    UILabel *tempLabel;
    tempLabel = (UILabel *)[cell viewWithTag:1];
    tempLabel.text = theFetchedMeme.screen_name;
    tempLabel = (UILabel *)[cell viewWithTag:5];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setLocale:[NSLocale currentLocale]];
	[dateFormatter setDateStyle:NSDateFormatterMediumStyle];
	[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
	if(currentFetch == FTReplyView)
		tempLabel.text = [dateFormatter stringFromDate:theFetchedMeme.date_time];
	else
		tempLabel.text = [dateFormatter stringFromDate:theFetchedMeme.dt_last_movement];
	[dateFormatter release];
	
	// avatar clickable image (this one assumes all user in section 0) screen_name is passed in transparent text.
	UIButton *tempButton = (UIButton *)[cell viewWithTag:6];
	UIImage *tempImage;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
	if([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
		tempImage = [[UIImage alloc] initWithCGImage:[[UIImage imageWithData:theFetchedMeme.user.avatar_44] CGImage] 
											   scale:[[UIScreen mainScreen] scale]
										 orientation:UIImageOrientationUp];
	else
#endif
		tempImage = [[UIImage alloc] initWithCGImage:[[UIImage imageWithData:theFetchedMeme.user.avatar_44] CGImage]];
	[tempButton setBackgroundImage:tempImage forState:UIControlStateNormal];
	[tempImage release];
	[tempButton setTitle:[NSString stringWithFormat: @"%lu", (unsigned long) indexPath.row] forState:UIControlStateNormal];
	
	// Reply and disclosure
	tempLabel = (UILabel *)[cell viewWithTag:4];
	if([theFetchedMeme.qta_replies intValue] == 0 || self.replyTo != nil)
	{
		// Hide also disclosure sign if simple text
		if([theFetchedMeme.meme_type isEqualToString:@"text"])
			tempLabel.text = @"";
		else
			tempLabel.text = @">";
	}
	else
		tempLabel.text = [NSString stringWithFormat:@"%@ >", theFetchedMeme.qta_replies];

	// things that depend on the kind of meme
	
	// This is the calculated size of "content"
	tempLabel = (UILabel *)[cell viewWithTag:3];
	tempLabel.text = theFetchedMeme.content;
	tempLabel.font = [UIFont systemFontOfSize:13.0f];
	tempLabel.lineBreakMode = UILineBreakModeWordWrap;
	CGRect labelFrame = tempLabel.frame;
	labelFrame.size.width = kTextWidth;
	tempLabel.frame = labelFrame;
	[tempLabel sizeToFit];
	
	UIImageView *tempView = (UIImageView *)[cell viewWithTag:7];
	if([theFetchedMeme.meme_type isEqualToString:@"image"])
		tempView.image = imgCamera;
	else if([theFetchedMeme.meme_type isEqualToString:@"video"])
		tempView.image = imgVideo;
	else if([theFetchedMeme.meme_type isEqualToString:@"link"])
		tempView.image = imgLink;
	else // should be "text" only, but who knows
		tempView.image = nil;
	
	// Set the "new"s'...
	tempView = (UIImageView *)[cell viewWithTag:8];
	if([theFetchedMeme.new_meme boolValue])
		tempView.image = imgBlackFlag;
	else if([theFetchedMeme.new_replies boolValue])
		tempView.image = imgWhiteFlag;
	else
		tempView.image = imgSemplice;
	// "Private" memes
	if([theFetchedMeme.private_meme boolValue])
	{
		((UIImageView *)[cell viewWithTag:10]).image = imgLock;
		tempLabel = (UILabel *)[cell viewWithTag:2];
		tempLabel.text = theFetchedMeme.sent_to;
	}
	else
	{
		tempLabel = (UILabel *)[cell viewWithTag:2];
		tempLabel.text = theFetchedMeme.user.real_name;
		// "Special" only if not private! Mark also state for parent marking (if needed)
		if([theFetchedMeme.special boolValue])
		{
			((UIImageView *)[cell viewWithTag:10]).image = imgStar;
			if(currentFetch == FTReplyView)
			{
				specialThread = YES;
				DLog(@"Set specialThread to YES");
			}
		}
		else
			((UIImageView *)[cell viewWithTag:10]).image = imgNothing;
	}
	// 11 is "reshared"
	((UIImageView *)[cell viewWithTag:11]).hidden = ![theFetchedMeme.is_reshare boolValue];
	// 12 is "favorite"
	((UIImageView *)[cell viewWithTag:12]).hidden = ![theFetchedMeme.is_favorite boolValue];
	
    return cell;
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	float retVal;
	Meme *theFetchedMeme = [theMemeList objectAtIndexPath:indexPath];
	if(theFetchedMeme)
	{
		CGSize theSize = [theFetchedMeme.content sizeWithFont:[UIFont systemFontOfSize:13.0f] constrainedToSize:CGSizeMake(kTextWidth, FLT_MAX) lineBreakMode:UILineBreakModeWordWrap];
		retVal = theSize.height + kHeigthBesideText;
	}
	else
	{
		ALog(@"### Invalid Fetched Meme @ heightForRowAtIndexPath:%@. Watermark: %d", indexPath.row, self.watermark);
		retVal = kHeigthBesideText;
	}
	if((currentFetch == FTAll || currentFetch == FTReplyView) && indexPath.row == (self.watermark - 1))
	{
		DLog(@"heightForRowAtIndexPath set watermark st row %d", self.watermark);
		retVal += kExtraHeightForReload;
	}
	return retVal;
}

//- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
//{
//	
//}

//- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section 
//{ 
//    id <NSFetchedResultsSectionInfo> sectionInfo = [[theMemeList sections] objectAtIndex:section];
//    return [sectionInfo name];
//}
//
- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView 
{
    return [theMemeList sectionIndexTitles];
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index 
{
    return [theMemeList sectionForSectionIndexTitle:title atIndex:index];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath 
{
	[tableView deselectRowAtIndexPath:indexPath animated:NO];

	Meme *selectedMeme = ((Meme *)[theMemeList objectAtIndexPath:indexPath]);
	[Meemi markMemeRead:selectedMeme.id];
	
	// if we are at a meme list level (we need it for reply) just push another controller, same kind of this one. :)
	if(self.replyTo == nil)
	{
		WithFriendsController *controller = [[WithFriendsController alloc] initWithNibName:@"WithFriendsController" bundle:nil];
		controller.replyTo = selectedMeme.id;
		controller.replyScreenName = selectedMeme.screen_name;
		controller.replyQuantity = selectedMeme.qta_replies;
		[self.navigationController pushViewController:controller animated:YES];
		[controller release];
		controller = nil;
	}
	else // This is a reply thread list OR a meme without replies (show directly if needed or do nothing if text)
	{
		// If meme is a link, simply push a browser Windows on it.
		if([selectedMeme.meme_type isEqualToString:@"link"])
		{
			MemeOnWeb *controller = [[MemeOnWeb alloc] initWithNibName:@"MemeOnWeb" bundle:nil];
			controller.urlToBeLoaded = [selectedMeme.link stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
			[self.navigationController pushViewController:controller animated:YES];
			[controller release];
			controller = nil;
		}
		else if([selectedMeme.meme_type isEqualToString:@"image"])
		{
			MemeOnWeb *controller = [[MemeOnWeb alloc] initWithNibName:@"MemeOnWeb" bundle:nil];
			controller.urlToBeLoaded = [selectedMeme.image_url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
			[self.navigationController pushViewController:controller animated:YES];
			[controller release];
			controller = nil;
		}
		else if([selectedMeme.meme_type isEqualToString:@"video"])
		{
			DLog(@"video meme: %@", selectedMeme.video);
			// Check if the URl is valid
			if([NSURL URLWithString:selectedMeme.video])
			{	// URL is valid
				MemeOnWeb *controller = [[MemeOnWeb alloc] initWithNibName:@"MemeOnWeb" bundle:nil];
				controller.urlToBeLoaded = [selectedMeme.video stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				[self.navigationController pushViewController:controller animated:YES];
				[controller release];
				controller = nil;
			}
			else
			{
				// tell user that the video cannot be shown
				UIAlertView *theAlert = [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", @"")
																	message:NSLocalizedString(@"This video cannot be shown on this device", @"")
																   delegate:nil
														  cancelButtonTitle:@"OK" 
														  otherButtonTitles:nil] 
										 autorelease];
				[theAlert show];
			}
		}
		else 
		{
			// try to decode the content to see if an URL is present.
			NSString *urlRegex = @"\\bhttps?://[a-zA-Z0-9\\-.]+(?:(?:/[a-zA-Z0-9\\-._?,'+\\&%$=~*!():@\\\\]*)+)?";	
			if([selectedMeme.content isMatchedByRegex:urlRegex])
			{
				NSArray *matchedURLsArray = [selectedMeme.content componentsMatchedByRegex:urlRegex];
				DLog(@"matchedURLsArray: %@", matchedURLsArray);
				MemeOnWeb *controller = [[MemeOnWeb alloc] initWithNibName:@"MemeOnWeb" bundle:nil];
				controller.urlToBeLoaded = [[matchedURLsArray objectAtIndex:0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				[self.navigationController pushViewController:controller animated:YES];
				[controller release];
				controller = nil;					
			}
			
		}

	}
}


/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/


/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:YES];
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/


/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/


/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

#pragma mark Scrolling Overrides


// Labels: ☝☟

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
	if([self.laRuota isAnimating])
		checkForRefresh = NO;
	else
	{
		checkForRefresh = YES;  //  only check offset when dragging
		enoughDragging = NO;
	}
} 

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	if (checkForRefresh) 
	{
		if(scrollView.contentOffset.y >= 0.0f)
			return;

		if(!enoughDragging && scrollView.contentOffset.y < -65.0f)
		{
			self.headerLabel.text = NSLocalizedString(@"Release to Reload", @"");
			self.headerArrow.text = @"☝";
			enoughDragging = YES;
		}
		if(enoughDragging && scrollView.contentOffset.y > -65.0f)
		{
			self.headerLabel.text = NSLocalizedString(@"Pull down to Reload", @"");
			self.headerArrow.text = @"☟";
			enoughDragging = NO;
		}
	}
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView
				  willDecelerate:(BOOL)decelerate
{
	DLog(@"Scrolldrag end");
	enoughDragging = NO;
	checkForRefresh = NO;	
	if (scrollView.contentOffset.y <= - 65.0f) 
	{
		// start reloading, and reset controls...
		self.headerLabel.text = NSLocalizedString(@"Reloading...", @"");
		self.headerArrow.text = @" ";
		[self.laRuota startAnimating];
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.2];
		self.tableView.contentInset = UIEdgeInsetsMake(60.0f, 0.0f, 0.0f, 0.0f);
		[UIView commitAnimations];			
		[self loadMemePage];
	}
}


- (void)dealloc {
    [super dealloc];
}


@end

