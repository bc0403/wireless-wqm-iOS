# wireless-wqm-iOS
wireless (Bluetooth) water quality monitor for iOS

## Pod Configure
1. Exit Xcode, go to project location in terminal;
1. Type in `pod init`
1. Wait a moment, and then edit the generated Podfile, and insert `pot 'Charts'`, save the file and exit;
1. In terminal, type `pod install`;
1. Now, back to finder and open **.xcworkspace** (this is the file we are going to use from now onwards)
1. In targets "charts", go to build setting, and set swift to 4.0

## References
- http://www.hangar42.nl/hm10
- https://medium.com/@OsianSmith/creating-a-line-chart-in-swift-3-and-ios-10-2f647c95392e
