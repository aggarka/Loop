//
//  Item.swift
//  Loop
//
//  Created by Aggarwal, Kamal on 7/22/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
