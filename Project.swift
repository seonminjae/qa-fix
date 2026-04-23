import ProjectDescription

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.9",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "MARKETING_VERSION": "0.1.0",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "CODE_SIGN_STYLE": "Automatic",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ENABLE_APP_SANDBOX": "YES",
]

let project = Project(
    name: "QAFixMac",
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: "QAFixMac",
            destinations: .macOS,
            product: .app,
            bundleId: "com.fanmaum.QAFixMac",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .file(path: "QAFixMac/Info.plist"),
            sources: ["QAFixMac/**/*.swift"],
            resources: [
                "QAFixMac/Resources/Assets.xcassets",
                "QAFixMac/Resources/CRITICAL.md",
                "QAFixMac/Resources/SECURITY.md",
                "QAFixMac/Resources/UIKit-CRITICAL.md",
            ],
            entitlements: .file(path: "QAFixMac/Resources/QAFixMac.entitlements"),
            settings: .settings(base: [
                "PRODUCT_BUNDLE_IDENTIFIER": "com.fanmaum.QAFixMac",
                "COMBINE_HIDPI_IMAGES": "YES",
                "ENABLE_PREVIEWS": "YES",
                "ENABLE_APP_SANDBOX": "NO",
            ])
        ),
        .target(
            name: "QAFixMacTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.fanmaum.QAFixMacTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["QAFixMacTests/**/*.swift"],
            resources: ["QAFixMacTests/Fixtures/**"],
            dependencies: [.target(name: "QAFixMac")],
            settings: .settings(base: [
                "PRODUCT_BUNDLE_IDENTIFIER": "com.fanmaum.QAFixMacTests",
                "GENERATE_INFOPLIST_FILE": "YES",
                "BUNDLE_LOADER": "$(TEST_HOST)",
                "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/QAFixMac.app/Contents/MacOS/QAFixMac",
            ])
        ),
        .target(
            name: "CLISpike",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.fanmaum.QAFixMac.CLISpike",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["CLISpike/**/*.swift"],
            settings: .settings(base: [
                "PRODUCT_BUNDLE_IDENTIFIER": "com.fanmaum.QAFixMac.CLISpike",
                "ENABLE_APP_SANDBOX": "NO",
            ])
        ),
    ]
)
