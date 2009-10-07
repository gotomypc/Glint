//
//  FileDetailViewController.h
//  Glint
//
//  Created by Jakob Borg on 8/2/09.
//  Copyright 2009 Jakob Borg. All rights reserved.
//

#import "GlintAppDelegate.h"
#import "JBGPXReader.h"
#import "JBLocationMath.h"
#import "LapTimeViewController.h"
#import "RouteViewController.h"
#import <MessageUI/MessageUI.h>
#import <UIKit/UIKit.h>

@interface FileDetailViewController : UIViewController <MFMailComposeViewControllerDelegate> {
	GlintAppDelegate *delegate;
	JBGPXReader *reader;
	JBLocationMath *math;
	BOOL loading;

	UINavigationController *navigationController;
	UITableView *tableView;
	UITabBarItem *emailButton, *raceButton;
	NSArray *toolbarItems;
	LapTimeViewController *lapTimeController;
	RouteViewController *routeController;

	NSString *filename, *startTime, *endTime, *distance, *averageSpeed;
}

@property (retain, nonatomic) IBOutlet UINavigationController *navigationController;
@property (retain, nonatomic) NSArray *toolbarItems;
@property (retain, nonatomic) IBOutlet UITableView *tableView;
@property (retain, nonatomic) IBOutlet LapTimeViewController *lapTimeController;
@property (retain, nonatomic) IBOutlet RouteViewController *routeController;

- (void)prepareForLoad:(NSString*)newFilename;
- (void)loadFile:(NSString*)newFilename;
- (IBAction)sendFile:(id)sender;
- (IBAction)raceAgainstFile:(id)sender;
- (void)viewLapTimes;
- (void)viewOnMap;

@end
