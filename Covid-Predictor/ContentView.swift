//
//  ContentView.swift
//  Covid-Predictor
//
//  Created by Rohan Kumar on 7/27/22.
//

import SwiftUI
import Alamofire
import SwiftyJSON

let UIPink = Color.init(red: 1, green: 0.2, blue: 0.56)
let AIURL = "https://askai.aiclub.world/018cb7b9-ad1c-4c60-84a1-267fac249865"

// Observable Object to store all global variables in
// Allows Object to be passed as an Environment Object
class GlobalVars : ObservableObject {
    @Published var doObjectDetection = true
    @Published var numAttemptsToDetectObj = 0
}

struct ContentView: View {
    @State private var predictedAgeGroup = ""
    
    @State private var showSheet = false
    @State private var showingImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    
    @State private var inputImage: UIImage? = UIImage(named: "default")
    @State private var loadingText = " "
    @State private var isLoading = false

    @StateObject var globals = GlobalVars() // Creates global varible object
    

    
    var body: some View {
        VStack {
            // All Views with Struct at the end of its name are in ViewStructs.swift
            HeaderView().environmentObject(globals) // Passes global variables to header view
            Spacer()
            PredictionTextStruct(predictedAgeGroup: self.$predictedAgeGroup)
            isLoading ? LoadingCircleStruct() : nil // Shows loading Circle if isLoading == true
            InputImageViewStruct(inputImage: self.$inputImage)
            Spacer()
            SubmitButtonStruct(showingImagePicker: self.$showSheet)
            Spacer()
        } // Action Sheet allowing User to select between using Camera Roll or Taking a Live photo
        .actionSheet(isPresented: self.$showSheet) {
            ActionSheet(title: Text("Select Photo"), buttons: [
                .default(Text("Photo Library")) {
                    self.showingImagePicker = true
                    self.sourceType = .photoLibrary // Sets source type to Camera Roll
                },
                .default(Text("Take Photo")) {
                    self.showingImagePicker = true
                    // TODO: FIX CAMERA PRIVACY SETTINGS. DOES NOT WORK!!!
                    self.sourceType = .camera // Sets source type to Camera
                },
                .default(Text("Dismiss")) { self.showSheet = false }
            ] )
        }
        .sheet(isPresented: $showingImagePicker, onDismiss: processImage) { // Displays Image Picker with correct Source Type
            ImagePicker(image: self.$inputImage, isShown: self.$showingImagePicker, sourceType: self.sourceType)
        }
    }
    
    
    
    /// Is called after Submit Button is pressed and Image is selected.
    ///1. Turns off Image Picker.
    ///2. Processes API Call on entire image and outputs prediction.
    ///3. Applies Image Processing procedures on image.
    func processImage() {
        self.showingImagePicker = false // Removes Camera Roll Image picker from UI
        guard let inputImage = inputImage else {return} // Unwraps inputImage
        
        // Processes API Call on whole image
        processAPICall(image: inputImage, {(prediction, _) in
            // Displays prediction to UI
            let convertToAgeGroup = ["Kid": "6-20", "Young Adult": "21-35", "Adult": "36-59", "Elderly": "60+"] // Helper Dictionary to convert AI prediction to Age Group
            self.predictedAgeGroup = convertToAgeGroup[prediction] ?? ""
        })
        
        if globals.doObjectDetection {
            self.isLoading = true // Turns on loading view
            // Calls Object Detection Function
            globals.numAttemptsToDetectObj = 0
            detectObjsInImage(image: inputImage,
                              ROI_SIZE: (Int(inputImage.size.width / 5), Int(inputImage.size.width / 5)) )
        }
    }
    
    
    /// Processes API Call by sending image to global AI API link
    /// - parameter image: Image to be sent to AI API link.
    /// - parameter completion: completion handler to be executed using AI output once API call finishes.
    ///1. Is called on entire image to determine age range
    ///2. Is called on all subimages created by slidingWindow() function
    func processAPICall(image: UIImage, _
                        completion: @escaping (_ prediction:String, _ confidenceScore:Double) -> Void) {
        let apiCall = DispatchGroup()
        
        var prediction = ""
        var confidenceScore = 0.0
        // Pre processing before image is sent to AI
        let imageCompressed = image.jpegData(compressionQuality: 0.1)!
        let imageB64 = Data(imageCompressed).base64EncodedData()
        
        // Enters Dispatch Group before starting API Call
        apiCall.enter()
        
        AF.upload(imageB64, to: AIURL).responseDecodable(of: JSON.self) { response in
            switch response.result {
            case .success(let resultJSON):
                prediction = resultJSON["predicted_label"].string ?? ""
                
                // Calculates confidence score of prediction
                let confidence = resultJSON["score"]
                
                let convertToIndex = ["Kid": 0, "Young Adult": 1, "Adult": 2, "Elderly": 3] // Helper Dictionary to convert Labels to Indexes
                
                guard let confidenceIndex = convertToIndex[prediction] else { return } // Unwraps Index
                confidenceScore = confidence[confidenceIndex].rawValue as? Double ?? 0.0 // Sets confidenceScore to highest confidence among the categories outputted by the AI
            case .failure:
                print("Failure")
            } // END SWITCH-CASE STATEMENT
            
            // Leaves Dispatch Group after finishing API call
            apiCall.leave()
        } // END UPLOAD
        // Will Not be executed until apiCall dispatch group is empty
        apiCall.notify(queue: .main, execute: {
            // Calls Completion Handler after API Call finishes
            completion(prediction, confidenceScore)
        })
    }
    
    
    
    /// Applies all steps of object detection to output an array of non-overlapping rectangles which are drawn on inputImage
    /// - parameter image: image to be processed for object detection.
    /// - parameter ROI_SIZE: size of image used for slidingWindow() function (should be around the size of the object being detected) is set to 150x150 by default
    /// - parameter MIN_CONFIDENCE_SCORE: threshold value which must be crossed to add subimage to array - is set to 0.93 by default
    ///1. Calls imagePyramid() function and saves data in an array
    ///2. Passes all images in pyramid array into slidingWindow() function
    ///3. Sends all subimages produced by each slidingWindow() call to API
    ///4. Retrieves data from API and adds subimage to arrayOut if it passes a threshold confidenceScore
    ///5. Passes arrayOut to nonMaximumSuppression() function to get rid of overlapping rectangles
    ///6. Calls drawRectangleOnImage() function
    func detectObjsInImage(image: UIImage, ROI_SIZE: (Int, Int) = (150, 150), MIN_CONFIDENCE_SCORE:Double = 0.93) {
        // initialize constants used for the object detection procedure
        let PYR_SCALE = 1.25 // Scale factor used in imagePyramid() function (Higher Value = faster, less accurate)
        let WIN_STEP = 30 // Size of step that the Sliding Window is taking
        let INPUT_SIZE = (image.size.width, image.size.height) // Dimensions of Original Image
        
        var arrayOut:[((Int, Int, Int, Int), Double)] = [] // Array containing [ ( (X+Y Coordinates for rectangle), Confidence_Score ) ]
        let pyramid = image.imagePyramid(scale: PYR_SCALE, minSize: (150.0, 150.0))
        
        let origImage = image
        var imageCopy = image
        
        let apiCall = DispatchGroup() // Creates DispatchGroup for apiCall
        
        for img in pyramid {
            // Finds scale factor between current image in pyramid and original
            // Scale factor is used to calculate x and y values of ROI
            let scale = INPUT_SIZE.0 / img.size.width
            
            // Loops through sliding window for every image in image pyramid
            for (i, j, roiOrig) in img.slidingWindow(step: WIN_STEP, windowSize: ROI_SIZE) {
                // Applies Scale factor to calculate ROI's x and y values adjusted for the original image
                let I = Int(Double(i) * scale)
                let J = Int(Double(j) * scale)
                let w = Int(Double(ROI_SIZE.0) * scale)
                let h = Int(Double(ROI_SIZE.1) * scale)
                
                
                apiCall.enter() // Task Enters Dispatch Group before API Call Begins
                // Sends processed image to AI
                processAPICall(image: roiOrig, {(_, confidenceScore) in
                    
                    inputImage = imageCopy.drawRectanglesOnImage([(I, J, I+w, J+h)], color: .systemRed)
                    
                    // Appends Data to arrayOut if ROI has more than minimum confidence score
                    if confidenceScore >= MIN_CONFIDENCE_SCORE {
                        imageCopy = imageCopy.drawRectanglesOnImage([(I, J, I+w, J+h)], color: .systemOrange)
                        arrayOut.append( ((I, J, I+w, J+h), confidenceScore) )
                    }
            
                    apiCall.leave() // Task Leaves Dispatch Group after API call is completed
                    
                }) // END API CALL
                
            } // END INNER FOR LOOP
        } // END OUTER FOR LOOP
        
        // Executes after all API calls are completed
        apiCall.notify(queue: .main, execute: {
            if arrayOut.count > 0 {
                inputImage = origImage
                // If at least 1 object is detected, calls drawRectangleOnImage() function
                inputImage = inputImage!.drawRectanglesOnImage(nonMaximumSuppression(arrayOut), color: .systemGreen)
                self.isLoading = false
            } else if globals.numAttemptsToDetectObj <= 10 {
                // If no objects are detected, program retries detectObjsInImage() function with a  lower MIN_CONFIDENCE_SCORE up to 10 more times
                
                globals.numAttemptsToDetectObj += 1
                detectObjsInImage(image: image, ROI_SIZE: ROI_SIZE, MIN_CONFIDENCE_SCORE: MIN_CONFIDENCE_SCORE-0.02)
            } else {
                self.isLoading = false // Turns off loading screen when all attempts are used up
            }
        }) // END APICALL.NOTIFY BLOCK
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}



