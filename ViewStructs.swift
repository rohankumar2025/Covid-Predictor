//
//  ViewStructs.swift
//  Covid-Predictor
//
//  Created by Rohan Kumar on 7/27/22.
//

import Foundation
import SwiftUI

/// Displays animated circles when program is processing its API calls
struct LoadingCircleStruct : View {
    var body: some View {
        // Loading Circle View
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: UIPink))
            .scaleEffect(1.5)
        
    }
}

/// Displays InputImage passed in if it is not nil
struct InputImageViewStruct : View {
    @Binding var inputImage : UIImage? // Binds local inputImage to global inputImage
    var body: some View {
        if let img = inputImage { // Optional binding to unwrap variable
            // Displays inputImage if not nil
            Image(uiImage: img).resizable()
                .cornerRadius(10)
                .shadow(color: .black, radius: 2)
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 350)
        }
        
    }
}

/// Displays SubmitButton which turns on ImagePicker when pressed
struct SubmitButtonStruct : View {
    @Binding var showingImagePicker : Bool // Binds local showingImagePicker variable to global showingImagePicker
    var body: some View {
        Button("How Old Am I?"){
            showingImagePicker = true // Turns on ImagePicker sheet
        }
        .padding(.all, 14.0)
        .background(UIPink)
        .foregroundColor(.white)
        .cornerRadius(10)
        .font(.title)
    }
}

/// Displays Predicted Age Text
struct PredictionTextStruct : View {
    @Binding var predictedAgeGroup : String
    var body: some View {
        Group {
            Text("Your Calculated Age:")
                .font(.system(size: 30))
                .fontWeight(.medium)
            
            Spacer(minLength: 5)
            
            // Text that displays Predicted Age Group
            Text(predictedAgeGroup)
                .font(.largeTitle)
        }
        .foregroundColor(.gray)
    }
}

