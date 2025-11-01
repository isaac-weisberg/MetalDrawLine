//
//  ViewController.swift
//  MetalDrawLine
//
//  Created by i.weisberg on 26/10/2025.
//

import UIKit
import MetalKit

class ViewController: UIViewController {
    let lineDrawer = LineDrawer()
    let metalView = MTKView()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        lineDrawer.attach(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metalView)
        
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
