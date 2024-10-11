import Cocoa
import CoreGraphics

func printModes(_ modes: [CGDisplayMode], current: CGDisplayMode) {
    for mode in modes.sorted(by: { $0.width < $1.width }) {
        print("\(mode == current ? "*": " ") \(mode.width)x\(mode.height)")
    }
}

func getDisplayID() -> CGDirectDisplayID? {
    if let screen = NSScreen.screens.first, let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
        return displayID
    }
    return nil
}

func getCurrentMode() -> CGDisplayMode? {
    if let displayID = getDisplayID(), let displayMode = CGDisplayCopyDisplayMode(displayID) {
        return displayMode
    }
    return nil
}

func getModes() -> [CGDisplayMode]? {
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    if let displayID = getDisplayID(), let current = getCurrentMode(), let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] {
        return modes.filter { mode in mode.width * current.height == mode.height * current.width }
    }
    return nil
}

func setMode(width: Int, height: Int, condition: (() -> Bool)? = nil, frequency: UInt32 = 10, quit: Bool = true) {
    guard let displayID = getDisplayID(), let current = getCurrentMode(), let modes = getModes() else {
        print("Unable to fetch available display modes")
        exit(1)
    }
    
    var chosen: CGDisplayMode? = nil
    for mode in modes {
        if mode.width == width && mode.height == height {
            chosen = mode
            break
        }
    }
    if let chosen = chosen {
        var isModeSet: Bool = false
        while true {
            if condition == nil || condition!() {
                if isModeSet == false {
                    CGDisplaySetDisplayMode(displayID, chosen, nil)
                    isModeSet = true
                }
            } else {
                if quit { break }
                if isModeSet {
                    CGDisplaySetDisplayMode(displayID, current, nil)
                    isModeSet = false
                }
            }
            sleep(frequency)
        }
    } else {
        print("Requested screen resolution not found. Available modes:")
        printModes(modes, current: current)
        exit(1)
    }
}

func checkScript(_ script: String) -> Bool {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", script]
    try? task.run()
    task.waitUntilExit()
    return task.terminationStatus == 0
}

func parseMode(mode: String) -> (Int, Int)? {
    let regex = try! Regex<(Substring, Substring, Substring)>("^(\\d+)x(\\d+)$")
    if let result = try? regex.wholeMatch(in: mode) {
        return (width: (result.output.1 as NSString).integerValue, height: (result.output.2 as NSString).integerValue)
    }
    return nil
}

var mode: (width: Int, height: Int)? = nil
var script: String? = nil
var frequency: Int = 10
var quit: Bool = true

let name = CommandLine.arguments.first ?? "switch-res"
let help = """
Usage: \(name) 1234x567 [-c|--check script] [-n|--no-quit] [-t|--time-step 10]
       \(name) -l|--list

  - check-script: shell script that determines if resolution should stay changed or revert back
  - time-step:    how often (in seconds) check-script is run
  - no-quit:      don't quit if check-script failed once
"""

if CommandLine.argc == 1 {
    print(help)
    exit(0)
}

var index = 1
while index < CommandLine.argc {
    let argument = CommandLine.arguments[index]
    if !argument.starts(with: "-") {
        if let parsedMode = parseMode(mode: argument) {
            mode = parsedMode
        } else {
            print("Incorrect resolution: \(argument)")
            exit(1)
        }
    } else if ["-c", "--check"].contains(argument) {
        index += 1
        if index >= CommandLine.argc {
            print("Expected value for key: \(argument)")
            exit(1)
        }
        script = CommandLine.arguments[index]
    } else if ["-n", "--no-quit"].contains(argument) {
        quit = false
    } else if ["-t", "--time-step"].contains(argument) {
        index += 1
        if index >= CommandLine.argc {
            print("Expected value for key: \(argument)")
            exit(1)
        }
        let value = CommandLine.arguments[index]
        if let _ = try? (try! Regex("^(\\d+)$")).wholeMatch(in: value) {
            frequency = (value as NSString).integerValue
        } else {
            print("Time step is not integer: \(value)")
            exit(1)
        }
    } else if ["--help", "-h"].contains(argument) {
        print(help)
        exit(0)
    } else if ["--list", "-l"].contains(argument) {
        if let modes = getModes(), let current = getCurrentMode() {
            printModes(modes, current: current)
            exit(0)
        } else {
            print("Unable to fetch available display modes")
            exit(1)
        }
    } else {
        print("Unexpected flag: \(argument)")
        exit(1)
    }
    index += 1
}

guard let mode = mode else {
    print("Resolution not found")
    exit(1)
}

var check: (() -> Bool)? = {
    if let script = script {
        return { checkScript(script) }
    }
    return nil
}()

setMode(width: mode.width, height: mode.height, condition: check, frequency: UInt32(frequency), quit: quit)
