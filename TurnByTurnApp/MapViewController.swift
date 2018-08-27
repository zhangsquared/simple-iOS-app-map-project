//
//  MapViewController.swift
//  TurnByTurnApp
//
//  Created by Zhang Zhang on 8/5/18.
//  Copyright © 2018 Zhang Zhang. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import AVFoundation // voice

class MapViewController: UIViewController,
    CLLocationManagerDelegate,
    UISearchBarDelegate,
    MKMapViewDelegate {
    
    // Mark: - outlets
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var directionInfo: UILabel!
    
    // Mark: - instance
    let locationManager = CLLocationManager()
    
    // Mark: - variables
    var currentCoordinate: CLLocationCoordinate2D!
    var steps = [MKRouteStep]()
    var currentPolyLine: MKPolyline!
    var speaker = AVSpeechSynthesizer()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setUpLocationManager()
        setUpMapView()
        setUpSearchBar()
    }
    
    private func setUpLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.startUpdatingLocation()
    }
    
    private func setUpMapView() {
        mapView.delegate = self
        
        // mapView can get location from locationManager
        mapView.userTrackingMode = .followWithHeading // user current location with a blue dot and facing direction
    }
    
    private func setUpSearchBar() {
        searchBar.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // Mark: - protocols
    /* Core Location */
    
    // get current location: if current location changed, callback function.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let currentL = locations.last {
//            print(currentL)
//        }
//        else {
//            print("location not found")
//        }
        
        // guard: check nill
        guard let currentLocation = locations.last else {
//            print("location not found")
            return
        }
        currentCoordinate = currentLocation.coordinate
    }
    
    // enter region
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("entering in regin list: \(region.identifier)")
        updateDirectionInstruction(stepCount: Int(region.identifier)!)
    }
    

    // Mark: - Logic
    
    /* Routes */
    
    // MKMapViewDelegate
    // display routes, callback function
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let render = MKPolylineRenderer(polyline: overlay as! MKPolyline)
            render.strokeColor = UIColor.blue
            render.lineWidth = 5
            return render
        }
        else if overlay is MKCircle {
            let circle = overlay as! MKCircle
            let render = MKCircleRenderer(circle: circle)
            render.strokeColor = UIColor.brown
            render.alpha = 0.3
            return render
        }
        else {
            return MKOverlayRenderer()
        }
    }
    
    // calculate routes
    func getDirection(to destinationMapItem: MKMapItem){
        // source
        let sourcePlaceMark = MKPlacemark(coordinate: currentCoordinate)
        let sourceMapItem = MKMapItem(placemark: sourcePlaceMark)
        
        // setup calculation for direction request
        let directionReq = MKDirectionsRequest()
        directionReq.source = sourceMapItem
        directionReq.destination = destinationMapItem
        directionReq.transportType = .automobile
        
        // make direction calculation
        let direction = MKDirections(request: directionReq)
        direction.calculate(completionHandler: {(res, err) in // async request
            if err != nil {
                print("calculate direction errors: \(err!)")
            }
            else {
                if let response = res {
                    let routes = response.routes // a lit of routes
                    let optimalRoute = routes.first! // choose the shortest one
                    
                    self.cleanPolyline()
                    
                    self.currentPolyLine = optimalRoute.polyline
                    // add polyline to map
                    self.mapView.addOverlays([self.currentPolyLine], level: .aboveRoads)
                    
                    self.steps = optimalRoute.steps
                    self.generationTurnByTurnInstruction(self.steps)
                    self.updateDirectionInstruction(stepCount: 0) // init the first instruction
                }
            }
        })
    }
    
    private func cleanPolyline() {
        if currentPolyLine != nil {
            mapView.removeOverlays([currentPolyLine])
        }
    }
    
    // turn by turn
    func generationTurnByTurnInstruction(_ steps: [MKRouteStep]) {
        cleanCircles()
        
        // calculate
        for (i, step) in steps.enumerated() {
            print("\(step.instructions, step.distance, step.polyline.coordinate, i)")
            let region = CLCircularRegion(center: step.polyline.coordinate, radius: 20, identifier: "\(i)")
            self.locationManager.startMonitoring(for: region)
            print("monitoredRegions count: \(locationManager.monitoredRegions.count)")
            
            let circle = MKCircle(center: region.center, radius: region.radius)
            mapView.add(circle)
        }
    }
    
    private func cleanCircles() {
        // stop monitoring
        locationManager.monitoredRegions.forEach {
            locationManager.stopMonitoring(for: $0) // $0: the first param
        }
        // clean circle UI
        let circles = mapView.overlays.filter { (x) -> Bool in
            x is MKCircle
        }
        mapView.removeOverlays(circles)
    }
    
    // update direction instructions, voice control
    func updateDirectionInstruction(stepCount: Int) {
        var info = "Calculating..."
        if stepCount == steps.count - 1 { // the last step -- "you have rearched your destination"
            info = "\(steps[stepCount].instructions)"
        }
        else {
            info = "\(steps[stepCount].instructions) and move \(steps[stepCount + 1].distance) meters"
        }
        // text
        directionInfo.text = info
        // voice
        speaker.speak(AVSpeechUtterance(string: info))
    }
    
    /* Search */
    
    // clean map
    func cleanMap() {
        directionInfo.text = ""
        cleanAnnotations()
        cleanPolyline()
        cleanCircles()
    }
    
    private func cleanAnnotations() {
        mapView.removeAnnotations(mapView.annotations)
    }
    
    // UISearchBarDelegate
    // search map, callback function
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // disable search after search pressed
        searchBar.endEditing(true)
        cleanMap()
        
        // setup serach request
        let localSearchReq = MKLocalSearchRequest()
        localSearchReq.naturalLanguageQuery = searchBar.text
        let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let region = MKCoordinateRegion(center: currentCoordinate, span: span)
        localSearchReq.region = region
        
        // make search request
        let localSearch = MKLocalSearch(request: localSearchReq)
        localSearch.start(completionHandler: {(res, err) in // async request
            if err != nil {
                print("search response error: \(String(describing: err))")
            }
            else {
                let results = res?.mapItems // a list of search results
                guard let res = results else {
                    return
                }
                self.displayAnnotation(mapItems: res) // self is bind(this)
            }
        })
    }
    
    
    /* Annotations (Pins) */
    
    // display annotations
    func displayAnnotation(mapItems: [MKMapItem]) {
        for item in mapItems {
            // setup destination pin
            let annotation = MKPointAnnotation()
            annotation.title = item.name // name
            annotation.subtitle = item.placemark.title // address
            annotation.coordinate = item.placemark.coordinate // where to pin
            
            // add pin to mapview
            mapView.addAnnotation(annotation)
        }
    }
    
    // MKMapViewDelegate
    // display bubble, translate annotation object into annotation view
    // event driven, going through annotation one by one
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // user location pin
        if annotation is MKUserLocation {
            return nil
        }
        let identifier = "SearchResult"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        // when used for the first time, view will be nil
        // otherwise the view is reusable, don't need to created again
        // MKAnnotationView is the base view, MKPinAnnotationView is the derived view
        if annotationView == nil {
            let annotationPinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            
            // drop animates
            annotationPinView.animatesDrop = true
            // display name, titles and bubble(callout)
            annotationPinView.canShowCallout = true
            // bubble right space
            annotationPinView.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            
            annotationView = annotationPinView
        }
        annotationView?.annotation = annotation
        return annotationView
    }
    
    // MKMapViewDelegate
    // click bubble trigger event
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                              calloutAccessoryControlTapped control: UIControl) {
        let annotation = view.annotation as! MKPointAnnotation
        let pm = MKPlacemark(coordinate: annotation.coordinate)
        getDirection(to: MKMapItem(placemark: pm))
    }

}
