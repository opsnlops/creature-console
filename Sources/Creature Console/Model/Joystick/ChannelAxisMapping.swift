import Foundation
import SwiftUI
import OSLog

/**
 The channel on the creature. This are defined as the "inputs" in the creature JSON.
 
 Normally there's 10 per creature. Not all have to be used. If I add more than ten in the future, make sure to update this file 😅
 */
enum InputChannel: Int, CaseIterable, Identifiable, Hashable {
    case channel0 = 0, channel1, channel2, channel3, channel4, channel5, channel6, channel7, channel8, channel9
    
    var id: Int { self.rawValue }
    
    var description: String {
        switch self {
        case .channel0: return "Channel 0"
        case .channel1: return "Channel 1"
        case .channel2: return "Channel 2"
        case .channel3: return "Channel 3"
        case .channel4: return "Channel 4"
        case .channel5: return "Channel 5"
        case .channel6: return "Channel 6"
        case .channel7: return "Channel 7"
        case .channel8: return "Channel 8"
        case .channel9: return "Channel 9"
            
        }
    }
}

/**
 Joystick axis
 */
enum JoystickAxis: Int, CaseIterable, Identifiable, Hashable {
    case axis0 = 0, axis1, axis2, axis3, axis4, axis5, axis6, axis7
    
    var id: Int { self.rawValue }
    
    var description: String {
        return "Axis \(self.rawValue)"
    }
}

/**
 Custom names, to allow the user to set something that's meaningful to them
 
 These could also be read in from the creature's JSON config file
 */
class ChannelAxisMapping: ObservableObject {
    @Published var mappings: [InputChannel: JoystickAxis]
    @Published var customNames: [InputChannel: String]
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "ChannelAxisMapping")
    
    init(mappings: [InputChannel: JoystickAxis] = [:], customNames: [InputChannel: String] = [:]) {
        self.mappings = mappings
        self.customNames = customNames
        self.loadMappings()
        self.loadCustomNames()
    }
    
    func loadMappings() {
        // Implementation to load mappings from UserDefaults
        let defaults = UserDefaults.standard
        if let savedMappings = defaults.object(forKey: "channelAxisMappings") as? [Int: Int] {
            self.mappings = savedMappings.reduce(into: [InputChannel: JoystickAxis]()) { result, pair in
                if let channel = InputChannel(rawValue: pair.key),
                   let axis = JoystickAxis(rawValue: pair.value) {
                    result[channel] = axis
                }
            }
        }
    }
    
    func loadCustomNames() {
        // Implementation to load custom names from UserDefaults
        let defaults = UserDefaults.standard
        if let savedNames = defaults.object(forKey: "channelCustomNames") as? [Int: String] {
            self.customNames = savedNames.reduce(into: [InputChannel: String]()) { result, pair in
                if let channel = InputChannel(rawValue: pair.key) {
                    result[channel] = pair.value
                }
            }
        }
    }
    
    func saveMappings() {
        // Implementation to save mappings to UserDefaults
        let defaults = UserDefaults.standard
        let savedMappings = mappings.reduce(into: [Int: Int]()) { result, pair in
            result[pair.key.rawValue] = pair.value.rawValue
        }
        defaults.set(savedMappings, forKey: "channelAxisMappings")
    }
    
    func saveCustomNames() {
        // Implementation to save custom names to UserDefaults
        let defaults = UserDefaults.standard
        let savedNames = customNames.reduce(into: [Int: String]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
        defaults.set(savedNames, forKey: "channelCustomNames")
    }
    
    
    // Method to register default channel-axis mappings and custom names
    func registerDefaultMappingsAndNames() {
       let channelAxisMappings = self.generateDefaultChannelAxisMappings()
       let channelCustomNames = self.generateDefaultChannelCustomNames()

       // Serialize the dictionaries into Data objects for UserDefaults
       if let channelAxisMappingsData = self.serializeDictionary(channelAxisMappings),
          let channelCustomNamesData = self.serializeDictionary(channelCustomNames) {
           UserDefaults.standard.register(defaults: ["channelAxisMappings": channelAxisMappingsData, "channelCustomNames": channelCustomNamesData])
       } else {
           logger.error("Unable to register defeault channel and axis names")
       }
    }

    // Generate default mappings - same as before
    private func generateDefaultChannelAxisMappings() -> [Int: Int] {
       var mappings = [Int: Int]()
       InputChannel.allCases.forEach { channel in
           mappings[channel.rawValue] = channel.rawValue
       }
       return mappings
    }

    // Generate default custom names - same as before
    private func generateDefaultChannelCustomNames() -> [Int: String] {
       var names = [Int: String]()
       InputChannel.allCases.forEach { channel in
           names[channel.rawValue] = channel.description
       }
       return names
    }

    
    func serializeDictionary<T>(_ dictionary: [Int: T]) -> Data? {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: dictionary, requiringSecureCoding: false)
            return data
        } catch {
            logger.error("Unable to serialize dictionary: \(error)")
            return nil
        }
    }
    
    func deserializeDictionary<T>(_ data: Data) -> [Int: T]? {
        do {
            if let dictionary = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [Int: T] {
                return dictionary
            } else {
                logger.error("Error: Could not deserialize data into a dictionary.")
                return nil
            }
        } catch {
            logger.error("Error: Unable to deserialize data. \(error)")
            return nil
        }
    }

}

extension ChannelAxisMapping {
    static var mock: ChannelAxisMapping {
        let mockMapping = ChannelAxisMapping()
        // Populate the mock with sample data
        mockMapping.mappings = [
            .channel0: .axis0,
            .channel1: .axis1,
            // Add more mock mappings as needed
        ]
        mockMapping.customNames = [
            .channel0: "Mock Channel 0",
            .channel1: "Mock Channel 1",
            // Add more mock names as needed
        ]
        return mockMapping
    }
}

