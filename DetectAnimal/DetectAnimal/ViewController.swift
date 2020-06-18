//
//  ViewController.swift
//  MachineLearningTestApp
//
//  Created by Asif Mujtaba on 6/16/20.
//  Copyright © 2020 Asif Mujtaba. All rights reserved.
//

import UIKit
import AVKit
import Vision
import CoreML

class ViewController: UIViewController {
    
    @IBOutlet weak var resultsView: UIVisualEffectView!
    @IBOutlet weak var resultsLabel: UILabel!
    @IBOutlet weak var preview: UIView!
    
    let captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer!
    
    var videoCapture: VideoCapture!
    
    let semaphore = DispatchSemaphore(value: ViewController.maxInFlightBuffer)
    
    var classificationRequest = [VNCoreMLRequest]()
    var inFlightBuffer = 0
    static let maxInFlightBuffer = 2
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpCameraPreview()
        setUpVisionRequest()
    }

    func setUpCameraPreview() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        
        videoCapture.frameInterval = 1
        
        videoCapture.setUp(sessionPreset: .high) { success in
            if success {
                if let previewLayer = self.videoCapture.videoPreviewLayer {
                    self.preview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
            }
            
            self.videoCapture.start()
        }
    }
    
    fileprivate func resizePreviewLayer() {
        videoCapture.videoPreviewLayer?.frame = preview.bounds
    }
    
    lazy var visionModel: VNCoreMLModel =  {
        do {
            let model = try VNCoreMLModel(for: Animal().model)
            return model
        } catch {
            fatalError("Faile to get Model \(error)")
        }
    }()
    
    fileprivate func setUpVisionRequest() {
        
        for _ in 0..<ViewController.maxInFlightBuffer {
            let request = VNCoreMLRequest(model: visionModel) { (request, error) in
                if error != nil {
                    return
                }
                
                self.processRequest(request: request)
            }
            request.imageCropAndScaleOption = .centerCrop
            classificationRequest.append(request)
        }
    }
    
    fileprivate func processRequest(request: VNRequest) {
        DispatchQueue.main.async {
            guard let results = request.results as? [VNClassificationObservation] else {
                self.resultsLabel.text = "nothing found"
                return
            }
            
            let top3 = results.prefix(3).map{ observation in
                String(format: "%@ %.1f%%", observation.identifier, observation.confidence * 100)
            }
            
            self.resultsLabel.text = top3.joined(separator: "\n")

        }
    }
    
    fileprivate func classify(sampleBuffer: CMSampleBuffer) {
        //convert sampleBuffer into pixelBuffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        //Tell Vision about the orientation of the image.
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(UIDevice.current.orientation.rawValue))
        
        //get additional info from camera
        var options: [VNImageOption: Any] = [:]
        
        if let cameraIntrinsicMatrix = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)  {
            options[.cameraIntrinsics] = cameraIntrinsicMatrix
        }
        
        
        // The semaphore is used to block the VideoCapture queue and drop frames
        // when Core ML can't keep up.
        semaphore.wait()
        
        //TODO:
        
        let request = self.classificationRequest[inFlightBuffer]
        inFlightBuffer += 1
        if inFlightBuffer >= ViewController.maxInFlightBuffer {
          inFlightBuffer = 0
        }
//        let request = classificationRequest[0]
        
        //For better throughput, perform the handler in background
        //insted of on videoCapture queue
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer,
                                                orientation: orientation!,
                                                options: options)
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform request handler: \(error)")
            }
            self.semaphore.signal()
        }
    }
    
}

extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        classify(sampleBuffer: sampleBuffer)
    }
}
