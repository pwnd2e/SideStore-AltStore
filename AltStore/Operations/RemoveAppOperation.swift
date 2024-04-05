//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import minimuxer

@objc(RemoveAppOperation)
final class RemoveAppOperation: ResultOperation<InstalledApp>
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        installedApp.managedObjectContext?.perform {
            let resignedBundleIdentifier = installedApp.resignedBundleIdentifier
            
            do {
                try remove_app(resignedBundleIdentifier)
            } catch {
                return self.finish(.failure(error))
            }
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                self.progress.completedUnitCount += 1
                
                let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                installedApp.isActive = false
                self.finish(.success(installedApp))
            }
        }
    }
}

