//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import SwiftUI
import Cocoa
import CoreImage.CIFilterBuiltins

class MFASetupScreen: NSViewController {
    
    var detailsScreen:NSViewController?;
    var identity:ZitiIdentity?;
    let context = CIContext();
    let filter = CIFilter.qrCodeGenerator();
    var url:String = "";
    @IBOutlet var BarCode: NSImageView!
    @IBOutlet var SecretCode: NSTextField!
    @IBOutlet var SecretToggle: NSTextField!
    @IBOutlet var LinkButton: NSTextField!
    @IBOutlet var CloseButton: NSImageView!
    @IBOutlet var AuthButton: NSBox!
    
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    
    override func viewDidLoad() {
        SetupCursor();
        url = "https://netfoundry.io"; // get url from MFA object
        SecretCode.stringValue = "3143423423"; // get from MFA object
        
        let data = Data(url.utf8);
        filter.setValue(data, forKey: "inputMessage");
        let transform = CGAffineTransform(scaleX: 3, y: 3)
        if let qrCodeImage = filter.outputImage?.transformed(by: transform) {
            if let qrCodeCGImage = context.createCGImage(qrCodeImage, from: qrCodeImage.extent) {
                BarCode.image = redimensionaNSImage(image: NSImage(cgImage: qrCodeCGImage, size: .zero), size: NSSize(width: 200, height: 200));
            }
        }
    }
    
    func redimensionaNSImage(image: NSImage, size: NSSize) -> NSImage {

        var ratio: Float = 0.0
        let imageWidth = Float(image.size.width)
        let imageHeight = Float(image.size.height)
        let maxWidth = Float(size.width)
        let maxHeight = Float(size.height)

        if (imageWidth > imageHeight) {
            ratio = maxWidth / imageWidth;
        } else {
            ratio = maxHeight / imageHeight;
        }

        // Calculate new size based on the ratio
        let newWidth = imageWidth * ratio
        let newHeight = imageHeight * ratio

        let imageSo = CGImageSourceCreateWithData(image.tiffRepresentation! as CFData, nil)
        let options: [NSString: NSObject] = [
            kCGImageSourceThumbnailMaxPixelSize: max(imageWidth, imageHeight) * ratio as NSObject,
            kCGImageSourceCreateThumbnailFromImageAlways: true as NSObject
        ]
        let size1 = NSSize(width: Int(newWidth), height: Int(newHeight))
        let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSo!, 0, options as CFDictionary).flatMap {
            NSImage(cgImage: $0, size: size1)
        }

        return scaledImage!
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func LinkClicked(_ sender: NSClickGestureRecognizer) {
        let mfaurl = URL (string: url)!;
        NSWorkspace.shared.open(mfaurl);
    }
    
    @IBAction func SecretClicked(_ sender: NSClickGestureRecognizer) {
        if (BarCode.isHidden) {
            BarCode.isHidden = false;
            SecretCode.isHidden = true;
            SecretToggle.stringValue = "Show Secret";
        } else {
            BarCode.isHidden = true;
            SecretCode.isHidden = false;
            SecretToggle.stringValue = "Show QR Code";
        }
    }
    
    @IBAction func SetupClicked(_ sender: NSClickGestureRecognizer) {
    }
    
    func SetupCursor() {
        let items = [SecretToggle, LinkButton, CloseButton, AuthButton];
        
        pointingHand = NSCursor.pointingHand;
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: pointingHand!);
        }
        
        pointingHand!.setOnMouseEntered(true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
        }

        arrow = NSCursor.arrow
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: arrow!);
        }
        
        arrow!.setOnMouseExited(true)
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: arrow!, userData: nil, assumeInside: true);
        }
    }
}
