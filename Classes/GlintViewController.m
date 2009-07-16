//
//  GlintViewController.m
//  Glint
//
//  Created by Jakob Borg on 6/26/09.
//  Copyright Jakob Borg 2009. All rights reserved.
//

#import "GlintViewController.h"

//
// Private methods
//
@interface GlintViewController ()
- (NSString*)formatTimestamp:(double)seconds maxTime:(double)max;
- (NSString*) formatDMS:(double)latLong;
- (NSString*)formatLat:(double)lat;
- (NSString*)formatLon:(double)lon;
- (bool)precisionAcceptable:(CLLocation*)location;
- (double) speedFromLocation:(CLLocation*)locA toLocation:(CLLocation*)locB;
- (double) bearingFromLocation:(CLLocation*)loc1 toLocation:(CLLocation*)loc2;
@end

//
// Background threads
//
@interface GlintViewController (backgroundThreads)
- (void)updateDisplay:(NSTimer*)timer;
- (void)takeAveragedMeasurement:(NSTimer*)timer;
@end

@implementation GlintViewController
@synthesize statusIndicator, positionLabel, elapsedTimeLabel, currentSpeedLabel, currentTimePerDistanceLabel, currentTimePerDistanceDescrLabel;
@synthesize totalDistanceLabel, statusLabel, averageSpeedLabel, bearingLabel, accuracyLabel;
@synthesize toolbar, compass, recordingIndicator, signalIndicator;

- (void)dealloc {
        self.statusIndicator = nil;
        self.positionLabel = nil;
        self.elapsedTimeLabel = nil;
        self.currentSpeedLabel = nil;
        self.currentTimePerDistanceLabel = nil;
        self.currentTimePerDistanceDescrLabel = nil;
        self.totalDistanceLabel = nil;
        self.statusLabel = nil;
        self.averageSpeedLabel = nil;
        self.bearingLabel = nil;
        self.accuracyLabel = nil;
        self.compass = nil;
        self.recordingIndicator = nil;
        [locationManager release];
        [goodSound release];
        [badSound release];
        [super dealloc];
}

- (void)viewDidLoad {
        [super viewDidLoad];
        
        locationManager = [[CLLocationManager alloc] init];
        locationManager.distanceFilter = 25.0;
        locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        locationManager.delegate = self;
        [locationManager startUpdatingLocation];
        
        badSound = [[JBSoundEffect alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Basso" ofType:@"aiff"]];
        goodSound = [[JBSoundEffect alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Purr" ofType:@"aiff"]];
        averagedMeasurements = 0;
        firstMeasurement  = nil;
        lastMeasurement = nil;
        totalDistance = 0.0;
        currentSpeed = -1.0;
        currentCourse = -1.0;
        gpxWriter = nil;
        lockTimer = nil;

        UIBarButtonItem *unlockButton = [[UIBarButtonItem alloc] initWithTitle:@"Unlock" style:UIBarButtonItemStyleBordered target:self action:@selector(unlock:)];
        UIBarButtonItem *disabledUnlockButton = [[UIBarButtonItem alloc] initWithTitle:@"Unlock" style:UIBarButtonItemStyleBordered target:self action:@selector(unlock:)];
        //UIBarButtonItem *sendButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(sendFiles:)];
        //UIBarButtonItem *playButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(startStopRecording:)];
        //UIBarButtonItem *stopButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPause target:self action:@selector(startStopRecording:)];
        //[sendButton setStyle:UIBarButtonItemStyleBordered];
        //[playButton setStyle:UIBarButtonItemStyleBordered];
        //[stopButton setStyle:UIBarButtonItemStyleBordered];
        UIBarButtonItem *sendButton = [[UIBarButtonItem alloc] initWithTitle:@"Files" style:UIBarButtonItemStyleBordered target:self action:@selector(sendFiles:)];
        UIBarButtonItem *disabledSendButton = [[UIBarButtonItem alloc] initWithTitle:@"Files" style:UIBarButtonItemStyleBordered target:self action:@selector(sendFiles:)];
        UIBarButtonItem *playButton = [[UIBarButtonItem alloc] initWithTitle:@"Record" style:UIBarButtonItemStyleBordered target:self action:@selector(startStopRecording:)];
        UIBarButtonItem *stopButton = [[UIBarButtonItem alloc] initWithTitle:@"Stop Recording" style:UIBarButtonItemStyleBordered target:self action:@selector(startStopRecording:)];
        [disabledUnlockButton setEnabled:NO];
        [disabledSendButton setEnabled:NO];
        lockedToolbarItems = [[NSArray arrayWithObject:unlockButton] retain];
        recordingToolbarItems = [[NSArray arrayWithObjects:disabledUnlockButton, disabledSendButton, stopButton, nil] retain];
        pausedToolbarItems = [[NSArray arrayWithObjects:disabledUnlockButton, sendButton, playButton, nil] retain];
        [toolbar setItems:lockedToolbarItems animated:YES];
        
        NSString *path=[[NSBundle mainBundle] pathForResource:@"unitsets" ofType:@"plist"];
        unitSets = [NSArray arrayWithContentsOfFile:path];
        [unitSets retain];
        
        if (USERPREF_DISABLE_IDLE)
                [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        if (USERPREF_ENABLE_PROXIMITY)
                [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
        
        self.positionLabel.text = @"-";
        self.accuracyLabel.text = @"-";
        self.elapsedTimeLabel.text = @"00:00:00";
        
        self.totalDistanceLabel.text = @"-";
        self.currentSpeedLabel.text = @"?";
        self.averageSpeedLabel.text = @"?";
        self.currentTimePerDistanceLabel.text = @"?";
        NSString* bundleVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        NSString* marketVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        self.statusLabel.text = [NSString stringWithFormat:@"Glint %@ build %@", marketVer, bundleVer];
        
        NSTimer* displayUpdater = [NSTimer timerWithTimeInterval:UPDATE_INTERVAL target:self selector:@selector(updateDisplay:) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:displayUpdater forMode:NSDefaultRunLoopMode];
        NSTimer* averagedMeasurementTaker = [NSTimer timerWithTimeInterval:USERPREF_MEASUREMENT_INTERVAL target:self selector:@selector(takeAveragedMeasurement:) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:averagedMeasurementTaker forMode:NSDefaultRunLoopMode];
}

- (void)viewWillDisappear:(BOOL)animated
{
        if (gpxWriter.inTrackSegment)
                [gpxWriter endTrackSegment];
        [gpxWriter endFile];
        
        [locationManager stopUpdatingLocation];
        locationManager.delegate = nil;
        
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
        [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
        
        [super viewWillDisappear:animated];
}

- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
        static CLLocation *last = nil;
        
        if ([self precisionAcceptable:newLocation]) {
                if (!firstMeasurement)
                        firstMeasurement = [[NSDate date] retain];
                if (last) {
                        totalDistance += [last getDistanceFrom:newLocation];
                        currentCourse = [self bearingFromLocation:last toLocation:newLocation];
                        currentSpeed = [self speedFromLocation:last toLocation:newLocation];
                }
                [last release];
                last = newLocation;
                [last retain];
                [locationManager setDistanceFilter:2*last.horizontalAccuracy];
        }
        
        [lastMeasurement release];
        lastMeasurement = [[NSDate date] retain];
}

- (IBAction)unlock:(id)sender
{
        if (recording)
                [toolbar setItems:recordingToolbarItems animated:YES];
        else
                [toolbar setItems:pausedToolbarItems animated:YES];
        
        if (lockTimer) {
                [lockTimer invalidate];
                [lockTimer release];
                lockTimer = nil;
        }
        lockTimer = [NSTimer timerWithTimeInterval:5.0 target:self selector:@selector(lock:) userInfo:nil repeats:NO];
        [lockTimer retain];
        [[NSRunLoop currentRunLoop] addTimer:lockTimer forMode:NSDefaultRunLoopMode];
}

- (IBAction)lock:(id)sender
{
        [toolbar setItems:lockedToolbarItems animated:YES];
        if (lockTimer) {
                [lockTimer invalidate];
                [lockTimer release];
                lockTimer = nil;
        }
}

- (IBAction)sendFiles:(id)sender {
        [(GlintAppDelegate *)[[UIApplication sharedApplication] delegate] switchToSendFilesView:sender];
}

- (IBAction)startStopRecording:(id)sender
{
        if (!recording) {
                recording = YES;
                [self.recordingIndicator setColor:[UIColor greenColor]];
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);	
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString* filename = [NSString stringWithFormat:@"%@/track-%@.gpx", documentsDirectory, [[NSDate date] description]];
                gpxWriter = [[GlintGPXWriter alloc] initWithFilename:filename];
                [gpxWriter beginFile];
                [gpxWriter beginTrackSegment];
                averagedMeasurements = 0;
        } else {
                recording = NO;
                [self.recordingIndicator setColor:[UIColor grayColor]];
                if (gpxWriter.inTrackSegment)
                        [gpxWriter endTrackSegment];
                [gpxWriter endFile];
                [gpxWriter release];
                gpxWriter = nil;
        }
        [toolbar setItems:lockedToolbarItems animated:YES];
}

//
// Private methods
//

- (NSString*)formatTimestamp:(double)seconds maxTime:(double)max {
        if (seconds > max || seconds < 0)
                return [NSString stringWithFormat:@"?"];
        else {
                int isec = (int) seconds;
                int hour = (int) (isec / 3600);
                int min = (int) ((isec % 3600) / 60);
                int sec = (int) (isec % 60);
                return [NSString stringWithFormat:@"%02d:%02d:%02d", hour, min, sec];
        }
}

- (NSString*) formatDMS:(double)latLong {
        int deg = (int) latLong;
        int min = (int) ((latLong - deg) * 60);
        double sec = (double) ((latLong - deg - min / 60.0) * 3600.0);
        return [NSString stringWithFormat:@"%02d° %02d' %02.02f\"", deg, min, sec];
}

- (NSString*)formatLat:(double)lat {
        NSString* sign = lat >= 0 ? @"N" : @"S";
        lat = fabs(lat);
        return [NSString stringWithFormat:@"%@ %@", [self formatDMS:lat], sign]; 
}

- (NSString*)formatLon:(double)lon {
        NSString* sign = lon >= 0 ? @"E" : @"W";
        lon = fabs(lon);
        return [NSString stringWithFormat:@"%@ %@", [self formatDMS:lon], sign]; 
}

- (bool)precisionAcceptable:(CLLocation*)location {
        static double minPrec = 0.0;
        if (minPrec == 0.0)
                minPrec = USERPREF_MINIMUM_PRECISION;
        double currentPrec = location.horizontalAccuracy;
        return currentPrec > 0.0 && currentPrec <= minPrec;
}

- (double) speedFromLocation:(CLLocation*)locA toLocation:(CLLocation*)locB {
        double td = [locA.timestamp timeIntervalSinceDate:locB.timestamp];
        if (td < 0.0)
                td = -td;
        if (td == 0.0)
                return 0.0;
        double dist = [locA getDistanceFrom:locB];
        return dist / td;
}

- (double) bearingFromLocation:(CLLocation*)loc1 toLocation:(CLLocation*)loc2 {
        double lat1 = loc1.coordinate.latitude / 180.0 * M_PI;
        double lon1 = -loc1.coordinate.longitude / 180.0 * M_PI;
        double lat2 = loc2.coordinate.latitude / 180.0 * M_PI;
        double lon2 = -loc2.coordinate.longitude / 180.0 * M_PI;
        double y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2-lon1);
        double x = sin(lon2-lon1) * cos(lat2);
        double t = atan2(y, x);
        double b = t / M_PI * 180.0 + 360.0;
        if (b >= 360.0)
                b -= 360.0;
        return b;
}

//
// Background threads
//

- (void)takeAveragedMeasurement:(NSTimer*)timer
{
        static bool hasWrittenPoint = NO;
        CLLocation *current = locationManager.location;
        if (recording) {
                if ([self precisionAcceptable:current]) {
                        averagedMeasurements++;
                        if (!gpxWriter.inTrackSegment)
                                [gpxWriter beginTrackSegment];
                        [gpxWriter addPoint:current];
                        hasWrittenPoint = YES;
                } else if (hasWrittenPoint && gpxWriter.inTrackSegment) {
                        [gpxWriter endTrackSegment];
                        hasWrittenPoint = NO;
                }
        }
}

- (void)updateDisplay:(NSTimer*)timer
{
        static BOOL prevStateGood = NO;
        static double distFactor = 0.0;
        static double speedFactor = 0.0;
        static NSString *distFormat = nil;
        static NSString *speedFormat = nil;
        
        bool stateGood = [self precisionAcceptable:locationManager.location];
        if (stateGood != prevStateGood) {
                if (stateGood) {
                        [goodSound play];
                        [self.signalIndicator setColor:[UIColor greenColor]];
                        self.statusIndicator.image = [UIImage imageNamed:@"green-sphere.png"];
                } else {
                        [badSound play];
                        [self.signalIndicator setColor:[UIColor redColor]];
                        self.statusIndicator.image = [UIImage imageNamed:@"red-sphere.png"];
                }
                prevStateGood = stateGood;
        }
        
        if (distFactor == 0) {
                int unitsetIndex = USERPREF_UNITSET;
                NSDictionary* units = [unitSets objectAtIndex:unitsetIndex];
                distFactor = [[units objectForKey:@"distFactor"] floatValue];
                speedFactor = [[units objectForKey:@"speedFactor"] floatValue];
                distFormat = [units objectForKey:@"distFormat"];
                speedFormat = [units objectForKey:@"speedFormat"];
        }
        
        CLLocation *current = locationManager.location;
        [current retain];
        
        if (current)
                self.positionLabel.text = [NSString stringWithFormat:@"%@\n%@\nelev %.0f m", [self formatLat: current.coordinate.latitude], [self formatLon: current.coordinate.longitude], current.altitude];
        if (current.verticalAccuracy < 0)
                self.accuracyLabel.text = [NSString stringWithFormat:@"±%.0f m h, ±inf v.", current.horizontalAccuracy];
        else
                self.accuracyLabel.text = [NSString stringWithFormat:@"±%.0f m h, ±%.0f m v.", current.horizontalAccuracy, current.verticalAccuracy];
        
        if (firstMeasurement)
                self.elapsedTimeLabel.text =  [self formatTimestamp:[[NSDate date] timeIntervalSinceDate:firstMeasurement] maxTime:86400];
        
        if (stateGood) {                
                double averageSpeed = 0.0;
                if (firstMeasurement && lastMeasurement)
                        averageSpeed  = totalDistance / [lastMeasurement timeIntervalSinceDate:firstMeasurement];
                self.averageSpeedLabel.text = [NSString stringWithFormat:speedFormat, averageSpeed*speedFactor];
                
                self.totalDistanceLabel.text = [NSString stringWithFormat:distFormat, totalDistance*distFactor];
                
                if (currentSpeed >= 0.0)
                        self.currentSpeedLabel.text = [NSString stringWithFormat:speedFormat, currentSpeed*speedFactor];
                else
                        self.currentSpeedLabel.text = @"?";
                
                double secsPerEstDist = USERPREF_ESTIMATE_DISTANCE * 1000.0 / currentSpeed;
                self.currentTimePerDistanceLabel.text = [self formatTimestamp:secsPerEstDist maxTime:86400];
                self.currentTimePerDistanceDescrLabel.text = [NSString stringWithFormat:@"per %.2f km", USERPREF_ESTIMATE_DISTANCE];
                
                self.statusLabel.text = [NSString stringWithFormat:@"%04d measurements", averagedMeasurements];
                
                if (currentCourse >= 0.0)
                        self.compass.course = currentCourse;
                else
                        self.compass.course = 0.0;
        }
        [current release];
}

@end
