//
//  SCServiceDetailTableViewController.swift
//  FerryServices_2
//
//  Created by Stefan Church on 26/07/2014.
//  Copyright (c) 2014 Stefan Church. All rights reserved.
//

import UIKit
import MapKit
import QuickLook

class ServiceDetailTableViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, MKMapViewDelegate {
    
    class Section {
        var title: String?
        var footer: String?
        var rows: [Row]
        
        var showHeader: Bool
        var showFooter: Bool
        
        init (title: String?, footer: String?, rows: [Row]) {
            self.title = title
            self.footer = footer
            self.rows = rows
            self.showHeader = true
            self.showFooter =  true
        }
    }
    
    enum Row {
        case Basic(identifier: String, title: String, action: () -> ())
        case Disruption(identifier: String, disruptionDetails: DisruptionDetails, action: () -> ())
        case NoDisruption(identifier: String, disruptionDetails: DisruptionDetails?, action: () -> ())
        case Loading(identifier: String)
        case TextOnly(identifier: String, text: String, attributedString: NSAttributedString)
    }
    
    struct MainStoryBoard {
        struct TableViewCellIdentifiers {
            static let basicCell = "basicCell"
            static let disruptionsCell = "disruptionsCell"
            static let noDisruptionsCell = "noDisruptionsCell"
            static let loadingCell = "loadingCell"
            static let textOnlyCell = "textOnlyCell"
        }
        struct Constants {
            static let headerMargin = CGFloat(16)
            static let contentInset = CGFloat(120)
            static let motionEffectAmount = CGFloat(10)
        }
    }
    
    @IBOutlet weak var constraintMapViewLeading: NSLayoutConstraint!
    @IBOutlet weak var constraintMapViewTop: NSLayoutConstraint!
    @IBOutlet weak var constraintMapViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var labelArea: UILabel!
    @IBOutlet weak var labelRoute: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var tableView: UITableView!
    
    var annotations: [MKPointAnnotation]?
    var dataSource: [Section] = []
    var mapMotionEffect: UIMotionEffectGroup!
    var refreshing: Bool = false
    var serviceStatus: ServiceStatus!
    var headerHeight: CGFloat!
    
    lazy var locations: [Location]? = {
        if let serviceId = self.serviceStatus.serviceId {
            return Location.fetchLocationsForSericeId(serviceId)
        }
        
        return nil
        }()
    
    // MARK: -
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    // MARK: - view lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = self.serviceStatus.area
        
        // configure header
        self.labelArea.text = self.serviceStatus.area
        self.labelRoute.text = self.serviceStatus.route
        
        self.labelArea.preferredMaxLayoutWidth = self.view.bounds.size.width - (MainStoryBoard.Constants.headerMargin * 2)
        self.labelRoute.preferredMaxLayoutWidth = self.view.bounds.size.width - (MainStoryBoard.Constants.headerMargin * 2)
        
        self.tableView.tableHeaderView!.setNeedsLayout()
        self.tableView.tableHeaderView!.layoutIfNeeded()
        
        self.headerHeight = self.tableView.tableHeaderView!.systemLayoutSizeFittingSize(UILayoutFittingCompressedSize).height
        self.tableView.tableHeaderView!.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.headerHeight)
        
        // if the visualeffect view goes past the top of the screen we want to keep showing mapview blur
        self.constraintMapViewTop.constant = -self.headerHeight
        
        // configure tableview
        self.tableView.backgroundColor = UIColor.clearColor()
        self.tableView.contentInset = UIEdgeInsetsMake(MainStoryBoard.Constants.contentInset, 0, 0, 0)
        self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(MainStoryBoard.Constants.contentInset, 0, 0, 0)
        
        let backgroundView = UIView(frame: CGRectMake(0, self.headerHeight, self.view.bounds.size.width, 1000))
        backgroundView.backgroundColor = UIColor.tealBackgroundColor()
        self.tableView.addSubview(backgroundView)
        self.tableView.sendSubviewToBack(backgroundView)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationDidBecomeActive:", name: UIApplicationDidBecomeActiveNotification, object: nil)
        
        self.tableView.rowHeight = UITableViewAutomaticDimension;
        self.tableView.estimatedRowHeight = 44.0;
        
        // map button
        let mapButton = UIButton(frame: CGRectMake(0, -MainStoryBoard.Constants.contentInset, self.view.bounds.size.width, self.view.bounds.size.height))
        mapButton.addTarget(self, action: "touchedButtonShowMap:", forControlEvents: UIControlEvents.TouchUpInside)
        self.tableView.addSubview(mapButton)
        self.tableView.sendSubviewToBack(mapButton)
        
        // map motion effect
        let horizontalMotionEffect = UIInterpolatingMotionEffect(keyPath: "center.x", type: UIInterpolatingMotionEffectType.TiltAlongHorizontalAxis)
        horizontalMotionEffect.minimumRelativeValue = -MainStoryBoard.Constants.motionEffectAmount
        horizontalMotionEffect.maximumRelativeValue = MainStoryBoard.Constants.motionEffectAmount
        
        let vertiacalMotionEffect = UIInterpolatingMotionEffect(keyPath: "center.y", type: UIInterpolatingMotionEffectType.TiltAlongVerticalAxis)
        vertiacalMotionEffect.minimumRelativeValue = -MainStoryBoard.Constants.motionEffectAmount
        vertiacalMotionEffect.maximumRelativeValue = MainStoryBoard.Constants.motionEffectAmount
        
        self.mapMotionEffect = UIMotionEffectGroup()
        self.mapMotionEffect.motionEffects = [horizontalMotionEffect, vertiacalMotionEffect]
        
        if let locations = self.locations {
            if locations.count > 0 {
                self.configureMapView()
            }
        }
        
        self.refresh()
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        // extend the mapview as the motion effect moves the edges
        self.constraintMapViewLeading.constant = -MainStoryBoard.Constants.motionEffectAmount
        self.constraintMapViewTrailing.constant = -MainStoryBoard.Constants.motionEffectAmount
        self.mapView.addMotionEffect(self.mapMotionEffect)
        
        if let selectedIndexPath = self.tableView.indexPathForSelectedRow() {
            self.tableView.deselectRowAtIndexPath(selectedIndexPath, animated: true)
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        // reset the mapview edges as they would be visible from an interactive pop gesture
        self.constraintMapViewLeading.constant = 0
        self.constraintMapViewTrailing.constant = 0
        self.mapView.removeMotionEffect(self.mapMotionEffect)
    }
    
    func applicationDidBecomeActive(notification: NSNotification) {
        self.refresh()
    }
    
    // MARK: - mapview configuration
    func configureMapView() {
        if let locations = self.locations {
            if locations.count == 0 {
                return
            }
            
            if let annotations = self.annotations {
                self.mapView.removeAnnotations(annotations)
            }
            
            let annotations: [MKPointAnnotation]? = locations.map { location in
                let annotation = MKPointAnnotation()
                annotation.title = location.name
                annotation.coordinate = CLLocationCoordinate2D(latitude: location.latitude!, longitude: location.longitude!)
                return annotation
            }
            
            self.annotations = annotations
            
            if self.annotations != nil {
                self.mapView.addAnnotations(self.annotations!)
            }
        }
    }
    
    // MARK: - ui actions
    @IBAction func touchedButtonShowMap(sender: UIButton) {
        self.showMap()
    }
    
    // MARK: - refresh
    func refresh() {
        if self.refreshing {
            return
        }
        
        self.refreshing = true
        
        self.dataSource = generateDatasourceWithDisruptionDetails(nil, refreshing: true)
        self.tableView.reloadData()
        
        self.fetchLatestDisruptionDataWithCompletion {
            self.refreshing = false
            self.tableView.reloadData()
        }
    }
    
    // MARK: - Datasource generation
    private func generateDatasourceWithDisruptionDetails(disruptionDetails: DisruptionDetails?, refreshing: Bool) -> [Section] {
        var sections = [Section]()
        
        //disruption section
        var disruptionRow: Row
        var footer: String?
        
        if refreshing {
            disruptionRow = Row.Loading(identifier: MainStoryBoard.TableViewCellIdentifiers.loadingCell)
        }
        else if disruptionDetails == nil {
            disruptionRow = Row.TextOnly(identifier: MainStoryBoard.TableViewCellIdentifiers.textOnlyCell, text: "Unable to fetch the disruption status for this service.", attributedString: NSAttributedString())
        }
        else {
            if let disruptionStatus = disruptionDetails?.disruptionStatus {
                switch disruptionStatus {
                case .Normal:
                    disruptionRow = Row.NoDisruption(identifier: MainStoryBoard.TableViewCellIdentifiers.noDisruptionsCell, disruptionDetails: disruptionDetails!, {})
                    
                case .Information:
                    var action: () -> () = {}
                    if disruptionDetails!.hasAdditionalInfo {
                        action = {
                            [unowned self] in
                            Flurry.logEvent("Show additional info")
                            self.showWebInfoViewWithTitle("Additional info", content: disruptionDetails!.additionalInfo!)
                        }
                    }
                    
                    disruptionRow = Row.NoDisruption(identifier: MainStoryBoard.TableViewCellIdentifiers.noDisruptionsCell, disruptionDetails: disruptionDetails!, action)
                    
                case .SailingsAffected, .SailingsCancelled:
                    if let disruptionInfo = disruptionDetails {
                        footer = disruptionInfo.lastUpdated
                        
                        disruptionRow = Row.Disruption(identifier: MainStoryBoard.TableViewCellIdentifiers.disruptionsCell, disruptionDetails: disruptionInfo, action: {
                            [unowned self] in
                            Flurry.logEvent("Show disruption information")
                            
                            var disruptionInformation = disruptionInfo.details ?? ""
                            if disruptionDetails!.hasAdditionalInfo {
                                disruptionInformation += "</p>"
                                disruptionInformation += disruptionDetails!.additionalInfo!
                            }
                            
                            self.showWebInfoViewWithTitle("Disruption information", content:disruptionInformation)
                        })
                    }
                    else {
                        disruptionRow = Row.TextOnly(identifier: MainStoryBoard.TableViewCellIdentifiers.textOnlyCell, text: "Unable to fetch the disruption status for this service.", attributedString: NSAttributedString())
                    }
                }
            }
            else {
                // no disruptionStatus
                disruptionRow = Row.NoDisruption(identifier: MainStoryBoard.TableViewCellIdentifiers.noDisruptionsCell, disruptionDetails: nil, {})
            }
        }
        
        let disruptionSection = Section(title: nil, footer: footer, rows: [disruptionRow])
        sections.append(disruptionSection)
        
        
        // timetable section
        var timetableRows = [Row]()
        
        // depatures if available
        if let routeId = self.serviceStatus.serviceId {
            if Trip.areTripsAvailableForRouteId(routeId, onOrAfterDate: NSDate()) {
                let departuresRow: Row = Row.Basic(identifier: MainStoryBoard.TableViewCellIdentifiers.basicCell, title: "Departures", action: {
                    [unowned self] in
                    self.showDepartures()
                })
                timetableRows.append(departuresRow)
            }
        }
        
        // summer timetable
        if isSummerTimetableAvailable() {
            let summerTimetableRow: Row = Row.Basic(identifier: MainStoryBoard.TableViewCellIdentifiers.basicCell, title: "Summer timetable", action: {
                [unowned self] in
                self.showSummerTimetable()
            })
            timetableRows.append(summerTimetableRow)
        }
        
        // winter timetable
        if isWinterTimetableAvailable() {
            let winterTimetableRow: Row = Row.Basic(identifier: MainStoryBoard.TableViewCellIdentifiers.basicCell, title: "Winter timetable", action: {
                [unowned self] in
                self.showWinterTimetable()
            })
            timetableRows.append(winterTimetableRow)
        }
        
        var route = "Timetable"
        if let actualRoute = serviceStatus.route {
            route = actualRoute
        }
        
        if timetableRows.count > 0 {
            let timetableSection = Section(title: "Timetables", footer: nil, rows: timetableRows)
            sections.append(timetableSection)
        }
        
        return sections
    }
    
    // MARK: - Utility methods
    private func fetchLatestDisruptionDataWithCompletion(completion: () -> ()) {
        if let serviceId = self.serviceStatus.serviceId {
            APIClient.sharedInstance.fetchDisruptionDetailsForFerryServiceId(serviceId) { disruptionDetails, routeDetails, error in
                if (error == nil) {
                    self.dataSource = self.generateDatasourceWithDisruptionDetails(disruptionDetails, refreshing: false)
                }
                else {
                    self.dataSource = self.generateDatasourceWithDisruptionDetails(nil, refreshing: false)
                }
                completion()
            }
        }
        else {
            completion()
        }
    }
    
    private func fetchLatestWeatherDataWithCompletion(completion: () -> ()) {
        if let locations = self.locations {
            let location = locations[1]
            switch (location.latitude, location.longitude) {
            case let (.Some(lat), .Some(lng)):
                WeatherAPIClient.sharedInstance.fetchWeatherForLat(lat, lng: lng) { weather, error in
                    println("Fetched weather")
                }
            default:
                println("Location does not contain lat and lng")
            }
        }
    }
    
    private func isWinterTimetableAvailable() -> Bool {
        if serviceStatus.serviceId == nil {
            return false
        }
        
        return NSFileManager.defaultManager().fileExistsAtPath(winterPath())
    }
    
    private func isSummerTimetableAvailable() -> Bool {
        if serviceStatus.serviceId == nil {
            return false
        }
        
        return NSFileManager.defaultManager().fileExistsAtPath(summerPath())
    }
    
    private func showWinterTimetable() {
        Flurry.logEvent("Show winter timetable")
        showPDFTimetableAtPath(winterPath(), title: "Winter timetable")
    }
    
    private func showSummerTimetable() {
        Flurry.logEvent("Show summer timetable")
        showPDFTimetableAtPath(summerPath(), title: "Summer timetable")
    }
    
    private func winterPath() -> String {
        return NSBundle.mainBundle().bundlePath.stringByAppendingPathComponent("Timetables/2014/Winter/\(serviceStatus.serviceId!).pdf")
    }
    
    private func summerPath() -> String {
        return NSBundle.mainBundle().bundlePath.stringByAppendingPathComponent("Timetables/2014/Summer/\(serviceStatus.serviceId!).pdf")
    }
    
    private func showPDFTimetableAtPath(path: String, title: String) {
        let previewViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewControllerWithIdentifier("TimetablePreview") as TimetablePreviewViewController
        previewViewController.serviceStatus = self.serviceStatus
        previewViewController.url = NSURL(string: path)
        previewViewController.title = title
        self.navigationController?.pushViewController(previewViewController, animated: true)
    }
    
    private func showMap() {
        Flurry.logEvent("Show map")
        let mapViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewControllerWithIdentifier("mapViewController") as MapViewController
        
        if let actualRoute = self.serviceStatus.route {
            mapViewController.title = actualRoute
        }
        else {
            mapViewController.title = "Map"
        }
        
        mapViewController.annotations = self.annotations
        self.navigationController?.pushViewController(mapViewController, animated: true)
    }
    
    private func showDepartures() {
        Flurry.logEvent("Show departures")
        if let routeId = self.serviceStatus.serviceId {
            let timetableViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewControllerWithIdentifier("timetableViewController") as TimetableViewController
            timetableViewController.routeId = routeId
            self.navigationController?.pushViewController(timetableViewController, animated: true)
        }
    }
    
    private func showWebInfoViewWithTitle(title: String, content: String) {
        let disruptionViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewControllerWithIdentifier("WebInformation") as WebInformationViewController
        disruptionViewController.title = title
        disruptionViewController.html = content
        self.navigationController?.pushViewController(disruptionViewController, animated: true)
    }

    private func calculateMapRectForAnnotations(annotations: [MKPointAnnotation]) -> MKMapRect {
        var mapRect = MKMapRectNull
        for annotation in annotations {
            let point = MKMapPointForCoordinate(annotation.coordinate)
            mapRect = MKMapRectUnion(mapRect, MKMapRect(origin: point, size: MKMapSize(width: 0.1, height: 0.1)))
        }
        return mapRect
    }

    
    // MARK: - UITableViewDatasource
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return dataSource.count
    }
    
    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if dataSource[section].showHeader {
            return UITableViewAutomaticDimension
        }
        else {
            return CGFloat.min
        }
    }

    func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if dataSource[section].showFooter {
            return UITableViewAutomaticDimension
        }
        else {
            return CGFloat.min
        }
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource[section].rows.count
    }
    
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return dataSource[section].title
    }
    
    func tableView(tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return dataSource[section].footer
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let row = dataSource[indexPath.section].rows[indexPath.row]
        
        switch row {
        case let .Basic(identifier, title, _):
            let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath) as UITableViewCell
            cell.textLabel!.text = title
            return cell
        case let .Disruption(identifier, disruptionDetails, _):
            let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath) as ServiceDetailDisruptionsTableViewCell
            cell.configureWithDisruptionDetails(disruptionDetails)
            return cell
        case let .NoDisruption(identifier, disruptionDetails, _):
            let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath) as ServiceDetailNoDisruptionTableViewCell
            cell.configureWithDisruptionDetails(disruptionDetails)
            return cell
        case let .Loading(identifier):
            let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath) as ServiceDetailLoadingTableViewCell
            cell.activityIndicatorView.startAnimating()
            return cell
        case let .TextOnly(identifier, text, attributedString):
            let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath) as ServiceDetailTextOnlyCell
            if text.isEmpty {
                cell.labelText.attributedText = attributedString
            }
            else {
                cell.labelText.text = text
            }
            return cell
        }
    }
    
    // MARK: - UITableViewDelegate
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let row = dataSource[indexPath.section].rows[indexPath.row]
        switch row {
        case let .Basic(_, _, action):
            action()
        case let .Disruption(_, _, action):
            action()
        case let .NoDisruption(_, disruptionDetails, action):
            if disruptionDetails != nil && disruptionDetails!.hasAdditionalInfo {
                action()
            }
        default:
            println("No action for cell")
        }
    }
    
    func tableView(tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        let header = view as UITableViewHeaderFooterView
        header.textLabel.textColor = UIColor.tealTextColor()
    }
    
    // MARK: - MKMapViewDelegate
    func mapView(mapView: MKMapView!, didSelectAnnotationView view: MKAnnotationView!) {
        mapView.deselectAnnotation(view.annotation, animated: false)
    }
    
    func mapView(mapView: MKMapView!, didAddAnnotationViews views: [AnyObject]!) {
        let rect = self.calculateMapRectForAnnotations(self.annotations!)
        let topInset = MainStoryBoard.Constants.contentInset + 20
        let bottomInset = self.mapView.frame.size.height - (MainStoryBoard.Constants.contentInset * 2) + 60
        let visibleRect = self.mapView.mapRectThatFits(rect, edgePadding: UIEdgeInsetsMake(topInset, 35, bottomInset, 35))
        self.mapView.setVisibleMapRect(visibleRect, animated: false)
    }
}
