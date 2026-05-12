// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "BtaAudienzz",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "BtaAudienzz",
            targets: ["BtaAudienzz"]
        )
    ],
    targets: [
        .target(
            name: "BtaAudienzz",
            path: "BtaAudienzz",
            exclude: ["BtaAudienzz.docc"]
        )
    ]
)
