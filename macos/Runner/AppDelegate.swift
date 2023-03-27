import Cocoa
import file_open_handler
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller : FlutterViewController = mainFlutterWindow?.contentViewController as! FlutterViewController
        let channel = FlutterMethodChannel.init(name: "logChannel", binaryMessenger: controller.engine.binaryMessenger)
        channel.setMethodCallHandler({
            (_ call: FlutterMethodCall, _ result: FlutterResult) -> Void in
            if ("openPython" == call.method) {
                let arguments = call.arguments
                result(self.shell(arguments as! String))
            }
        });
    }
    
    private func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        task.standardInput = nil
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        
        return output
    }
    
    override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        
        FileOpenHandlerPlugin.instance.handleFileOpen(pathname: filename);
        // Return true if your app opened the file successfully, false otherwise
        return true
    }
}
