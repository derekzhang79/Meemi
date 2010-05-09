//
//  WithFriendsController.m
//  Meemi
//
//  Created by Giacomo Tufano on 02/04/10.
//  Copyright 2010 Giacomo Tufano (gt@ilTofa.it). All rights reserved.
//

#import "WithFriendsController.h"
#import "MeemiAppDelegate.h"
#import "Meme.h"
#import "MemeOnWeb.h"

@implementation WithFriendsController

@synthesize memeCell, predicateString, searchString, replyTo, replyScreenName, currentPosition;

-(void)deviceShaken:(NSNotification *)note
{
	DLog(@"SHAKED!");
	// If session is not busy, reload.
	if(![Meemi sharedSession].isBusy)
		[(MeemiAppDelegate *)[[UIApplication sharedApplication] delegate] reloadMemes];
}

-(void)meemiIsBusy:(NSNotification *)note
{
	DLog(@"meemiIsBusy: dimming navButtons");
	self.navigationItem.rightBarButtonItem.enabled = self.navigationItem.leftBarButtonItem.enabled = NO;
}

-(void)meemiIsFree:(NSNotification *)note
{
	DLog(@"meemiIsFree: enabling navButtons");
	self.navigationItem.rightBarButtonItem.enabled = self.navigationItem.leftBarButtonItem.enabled = YES;
	// While we are at it, probably the session could have read something. :)
	[self.tableView reloadData];
}

-(void)setupFetch
{
	NSManagedObjectContext *context = [Meemi sharedSession].managedObjectContext;
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
			self.predicateString = @"reply_id == 0";
			break;
		case FTNew:
			self.predicateString = [NSString stringWithFormat:@"(new_meme == YES OR new_replies == YES) AND reply_id == 0"];
			break;
		case FTPvt:
			self.predicateString = [NSString stringWithFormat:@"private_meme == YES AND reply_id == 0"];
			break;
		case FTSpecial:
			self.predicateString = [NSString stringWithFormat:@"special == YES and reply_id == 0"];
			break;
		case FTReplyView:
			self.predicateString = [NSString stringWithFormat:@"reply_id == %@ OR id == %@", self.replyTo, self.replyTo];
			break;
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
		[theMemeList release];
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
}	

-(void)filterSelected
{
	currentFetch = ((UISegmentedControl *) (((UIBarButtonItem *)[self.toolbarItems objectAtIndex:1]).customView)).selectedSegmentIndex;
	DLog(@"in filterSelected for %d selected, filtering on '%@'", currentFetch, self.searchString);
	[self setupFetch];
}

-(void)loadMemePage
{
	DLog(@"loadMemePage called");
	[Meemi sharedSession].delegate = self;
	[[Meemi sharedSession] getNewMemesRepliesOf:self.replyTo screenName:self.replyScreenName from:0 number:20];
}

#pragma mark MeemiDelegate

-(void)meemi:(MeemiRequest)request didFailWithError:(NSError *)error
{
	UIAlertView *theAlert = [[[UIAlertView alloc] initWithTitle:@"Error"
														message:@"Error loading data, please try again later"
													   delegate:nil
											  cancelButtonTitle:@"OK" 
											  otherButtonTitles:nil] 
							 autorelease];
	[theAlert show];
}	

-(void)meemi:(MeemiRequest)request didFinishWithResult:(MeemiResult)result
{
	DLog(@"got replies");
	// If returning from "get new replies", get avatars if needed.
	if(request == MMGetNewReplies)
		[[Meemi sharedSession] updateAvatars];
	else // It's OK, update...
		[self setupFetch];
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
	// Make user choose if (s)he wants to reply with text or image
	UIActionSheet *chooseIt = [[[UIActionSheet alloc] initWithTitle:@"Reply with?" 
														   delegate:self 
												  cancelButtonTitle:@"Cancel"
											 destructiveButtonTitle:nil
												  otherButtonTitles:@"Text", @"Image", nil]
							   autorelease];
	[chooseIt showFromTabBar:(UITabBar *)[((MeemiAppDelegate *)[[UIApplication sharedApplication] delegate]).tabBarController view]];
	// Flows below to the ActionSheetDelegate function.
}	

#pragma mark UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	NSLog(@"Picked button #%d", buttonIndex);
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

#pragma mark Standard Stuff

- (void)viewDidLoad 
{
    [super viewDidLoad];

	if(self.replyTo == nil)
	{
		// Add a left button for reloading the meme list
		UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"02-redo" ofType:@"png"]] 
																		 style:UIBarButtonItemStylePlain 
																		target:((MeemiAppDelegate *)[[UIApplication sharedApplication] delegate]) 
																		action:@selector(reloadMemes)];
		
		self.navigationItem.leftBarButtonItem = reloadButton;
		[reloadButton release];
		
		UIBarButtonItem *markReadButton = [[UIBarButtonItem alloc] initWithTitle:@"Mark Read" 
																		   style:UIBarButtonItemStylePlain 
																		  target:((MeemiAppDelegate *)[[UIApplication sharedApplication] delegate]) 
																		  action:@selector(markReadMemes)];
		self.navigationItem.rightBarButtonItem  = markReadButton;
		[markReadButton release];
		
		NSArray *tempStrings = [NSArray arrayWithObjects:@"All", @"New", @"Private", @"Special", nil];
		UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		UISegmentedControl *theSegment = [[UISegmentedControl alloc] initWithItems:tempStrings];
		theSegment.segmentedControlStyle = UISegmentedControlStyleBar;
		theSegment.tintColor = [UIColor darkGrayColor];
		theSegment.momentary = NO;
		theSegment.selectedSegmentIndex = 0;
		currentFetch = FTAll;
		[theSegment addTarget:self action:@selector(filterSelected) forControlEvents:UIControlEventValueChanged];
		NSArray *toolbarItems = [NSArray arrayWithObjects:
								 spacer,
								 [[[UIBarButtonItem alloc] initWithCustomView:theSegment] autorelease], spacer, nil];
		self.toolbarItems = toolbarItems;
		[theSegment release];
		[spacer release];
		self.navigationController.toolbar.barStyle = UIBarStyleBlack;
		currentFetch = FTAll;
	}
	else
	{
		currentFetch = FTReplyView;
		self.title = NSLocalizedString(@"Thread", @"");
		// Add a right button for reply to the meme list
		UIBarButtonItem *replyButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose 
																					 target:self 
																					 action:@selector(replyToMeme:)];
		self.navigationItem.rightBarButtonItem = replyButton;
		[replyButton release];
		[self loadMemePage];
	}
	
	self.view.backgroundColor = [UIColor colorWithRed:0.67188 green:0.81641 blue:0.95703 alpha:1.0];
	 
	self.searchString = @"";
	self.currentPosition = [NSIndexPath indexPathForRow:0 inSection:0];
}

- (void)viewWillAppear:(BOOL)animated 
{
    [super viewWillAppear:animated];
	// And register to be notified for shaking and busy/not busy of Meemi session
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceShaken:) name:@"deviceShaken" object:nil];
	if(self.replyTo == nil)
	{
		if([Meemi sharedSession].isBusy)
			[self meemiIsBusy:nil];
		else
			[self meemiIsFree:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(meemiIsBusy:) name:kNowBusy object:nil];		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(meemiIsFree:) name:kNowFree object:nil];
	}
	[self setupFetch];
}

- (void)viewDidAppear:(BOOL)animated 
{
    [super viewDidAppear:animated];
	// toolBar only on "parent" list
	self.navigationController.toolbarHidden = (self.replyTo != nil);
	[self.tableView reloadData];
	[self.tableView scrollToRowAtIndexPath:self.currentPosition atScrollPosition:UITableViewScrollPositionTop animated:NO];
}


- (void)viewWillDisappear:(BOOL)animated 
{
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.navigationController.toolbarHidden = YES;
	if(theMemeList != nil)
	{
		theMemeList.delegate = nil;
		[theMemeList release];
		theMemeList = nil;
	}
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
	[theMemeList release];
}

#pragma mark NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller 
{
	[self.tableView reloadData];
}

#pragma mark Table view methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView 
{
    NSUInteger count = [[theMemeList sections] count];
	// "Official" workaround for problem in iPhone OS 3
    if (count == 0) 
        count = 1;
    return count;
}


// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
 	// "Official" workaround for problem in iPhone OS 3
	NSArray *sections = [theMemeList sections];
    NSUInteger count = 0;
    if ([sections count]) 
	{
        id <NSFetchedResultsSectionInfo> sectionInfo = [sections objectAtIndex:section];
        count = [sectionInfo numberOfObjects];
    }
    return count;
}

#define kTextWidth 263.0f
#define kHeigthBesideText 73.0f

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *CellIdentifier = @"MemeCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) 
	{
		[[NSBundle mainBundle] loadNibNamed:@"MemeCell" owner:self options:nil];
        cell = memeCell;
        self.memeCell = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
	// This is 172/209/245 the Meemi "formal" background
//	cell.contentView.backgroundColor = [UIColor colorWithRed:0.67188 green:0.81641 blue:0.95703 alpha:1.0];
//	cell.accessoryView.backgroundColor = [UIColor colorWithRed:0.67188 green:0.81641 blue:0.95703 alpha:1.0];
    Meme *theFetchedMeme = [theMemeList objectAtIndexPath:indexPath];
    UILabel *tempLabel;
    tempLabel = (UILabel *)[cell viewWithTag:1];
    tempLabel.text = theFetchedMeme.screen_name;
    tempLabel = (UILabel *)[cell viewWithTag:5];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setLocale:[NSLocale currentLocale]];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    tempLabel.text = [dateFormatter stringFromDate:theFetchedMeme.date_time];
	[dateFormatter release];
	UIImageView *tempView = (UIImageView *)[cell viewWithTag:6];
	tempView.image = [UIImage imageWithData:theFetchedMeme.user.avatar];
	
	tempLabel = (UILabel *)[cell viewWithTag:4];
	tempLabel.text = [NSString stringWithFormat:@"%@", theFetchedMeme.qta_replies];
	// Hid the reply quantity number if it is a thread view (no reply for sure)
	tempLabel.hidden = (self.replyTo != nil);
	
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
	
	tempView = (UIImageView *)[cell viewWithTag:7];
	if([theFetchedMeme.meme_type isEqualToString:@"image"])
		tempView.image = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"camera-verysmall" ofType:@"png"]];
	else if([theFetchedMeme.meme_type isEqualToString:@"video"])
		tempView.image = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"video-verysmall" ofType:@"png"]];
	else if([theFetchedMeme.meme_type isEqualToString:@"link"])
		tempView.image = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"link-verysmall" ofType:@"png"]];
	else // should be "text" only, but who knows
		tempView.image = nil;
	// Hide the "new" flags if meme is not new...
	if([theFetchedMeme.new_meme boolValue])
		((UIImageView *)[cell viewWithTag:8]).hidden = NO;
	else
		((UIImageView *)[cell viewWithTag:8]).hidden = YES;
	if([theFetchedMeme.new_replies boolValue])
		((UIImageView *)[cell viewWithTag:9]).hidden = NO;
	else
		((UIImageView *)[cell viewWithTag:9]).hidden = YES;
	if([theFetchedMeme.special boolValue])
		((UIImageView *)[cell viewWithTag:11]).hidden = NO;
	else
		((UIImageView *)[cell viewWithTag:11]).hidden = YES;
	// "Private" memes
	if([theFetchedMeme.private_meme boolValue])
	{
		((UIImageView *)[cell viewWithTag:10]).hidden = NO;
		tempLabel = (UILabel *)[cell viewWithTag:2];
		tempLabel.text = theFetchedMeme.sent_to;
	}
	else
	{
		((UIImageView *)[cell viewWithTag:10]).hidden = YES;
		tempLabel = (UILabel *)[cell viewWithTag:2];
		tempLabel.text = theFetchedMeme.user.real_name;
	}
	
    return cell;
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	Meme *theFetchedMeme = [theMemeList objectAtIndexPath:indexPath];
	CGSize theSize = [theFetchedMeme.content sizeWithFont:[UIFont systemFontOfSize:13.0f] constrainedToSize:CGSizeMake(kTextWidth, FLT_MAX) lineBreakMode:UILineBreakModeWordWrap];
	return theSize.height + kHeigthBesideText;
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
	Meme *selectedMeme = ((Meme *)[theMemeList objectAtIndexPath:indexPath]);
	// if we are at a meme list level, just push another controller, same kind of this one. :)
	if(self.replyTo == nil)
	{
		WithFriendsController *controller = [[WithFriendsController alloc] initWithNibName:@"WithFriendsController" bundle:nil];
		controller.replyTo = selectedMeme.id;
		controller.replyScreenName = selectedMeme.screen_name;
		[self.navigationController pushViewController:controller animated:YES];
		[controller release];
		controller = nil;
	}
	else // This is a reply thread list
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
		if([selectedMeme.meme_type isEqualToString:@"image"])
		{
			MemeOnWeb *controller = [[MemeOnWeb alloc] initWithNibName:@"MemeOnWeb" bundle:nil];
			controller.urlToBeLoaded = [selectedMeme.image_url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
			[self.navigationController pushViewController:controller animated:YES];
			[controller release];
			controller = nil;
		}
		if([selectedMeme.meme_type isEqualToString:@"video"])
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
			{	// tell user that the video cannot be shown
				// TODO: find the way to show this kind of video...
				// <object width="480" height="385"><param name="movie" value="http://www.youtube.com/v/GSFPQDEkc-k&hl=it_IT&fs=1&"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.youtube.com/v/GSFPQDEkc-k&hl=it_IT&fs=1&" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="480" height="385"></embed></object>
				UIAlertView *theAlert = [[[UIAlertView alloc] initWithTitle:@"Error"
																	message:@"This video cannot be shown on this device"
																   delegate:nil
														  cancelButtonTitle:@"OK" 
														  otherButtonTitles:nil] 
										 autorelease];
				[theAlert show];				
			}
		}
	}
	// Mark it read and remember where we were, btw...
	[[Meemi sharedSession] markMemeRead:selectedMeme.id];
	self.currentPosition = indexPath;
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


- (void)dealloc {
    [super dealloc];
}


@end

