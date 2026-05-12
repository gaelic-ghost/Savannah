//
//  SafariExtensionViewController.swift
//  SafariTourGuide
//
//  Created by Gale Williams on 5/12/26.
//

import SafariServices

class SafariExtensionViewController: SFSafariExtensionViewController {
    
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width:320, height:240)
        return shared
    }()

}
