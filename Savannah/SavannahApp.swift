//
//  SavannahApp.swift
//  Savannah
//
//  Created by Gale Williams on 5/12/26.
//

import SwiftUI
import CoreData

@main
struct SavannahApp: App {
    let persistenceController = PersistenceController.shared
    private let rpcServer = SavannahRPCServer()

    init() {
        rpcServer.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
