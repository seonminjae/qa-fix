# iOS 공통 보안 가이드 (SECURITY)

이 문서는 iOS 앱의 보안 취약점과 데이터 보호 가이드라인을 다룹니다.

---

## 1. 민감 데이터 저장 🔴 P0

### 1.1 Keychain 사용

**문제**: 민감 정보를 UserDefaults나 파일에 평문 저장

```swift
// ❌ 잘못된 예 - UserDefaults에 토큰 저장
UserDefaults.standard.set(accessToken, forKey: "token")
UserDefaults.standard.set(password, forKey: "password")

// ❌ 잘못된 예 - 파일에 평문 저장
let data = password.data(using: .utf8)
try? data?.write(to: fileURL)

// ✅ 올바른 예 - Keychain 사용
import Security

func saveToKeychain(key: String, value: String) throws {
    let data = value.data(using: .utf8)!
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.saveFailed
    }
}
```

### 1.2 민감 데이터 분류

| 데이터 유형 | 저장 위치 | 접근성 |
|------------|----------|--------|
| Access Token | Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| Refresh Token | Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| 비밀번호 | Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| 생체 인증 데이터 | Keychain + LAContext | `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` |
| 암호화 키 | Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| 사용자 설정 | UserDefaults | - |
| 캐시 데이터 | Cache Directory | - |

---

## 2. 네트워크 보안 🔴 P0

### 2.1 HTTPS 강제

**문제**: HTTP 통신으로 데이터 노출

```swift
// ❌ 잘못된 예
let url = URL(string: "http://api.example.com/login")

// ✅ 올바른 예
let url = URL(string: "https://api.example.com/login")
```

**Info.plist 설정**:
```xml
<!-- ❌ 모든 HTTP 허용 - 보안 취약 -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>

<!-- ✅ 특정 도메인만 예외 처리 -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>legacy-api.example.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <false/>
        </dict>
    </dict>
</dict>
```

### 2.2 Certificate Pinning 🟡 P1

**권장**: 중요 API에 인증서 피닝 적용

```swift
// URLSession delegate로 Certificate Pinning
class NetworkManager: NSObject, URLSessionDelegate {
    private let pinnedCertificates: [Data]
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let serverCertificateData = SecCertificateCopyData(certificate) as Data
        
        if pinnedCertificates.contains(serverCertificateData) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

---

## 3. 로깅 보안 🔴 P0

### 3.1 민감 정보 로깅 금지

```swift
// ❌ 잘못된 예
print("User token: \(accessToken)")
print("Password: \(password)")
NSLog("API Key: %@", apiKey)

// ✅ 올바른 예 - 마스킹 처리
print("User token: \(accessToken.prefix(4))****")

// ✅ 올바른 예 - DEBUG 빌드에서만 로깅
#if DEBUG
print("Debug info: \(debugData)")
#endif

// ✅ 올바른 예 - OSLog 사용 (민감 정보 제외)
import os.log

let logger = Logger(subsystem: "com.app", category: "network")
logger.info("Request sent to \(url, privacy: .public)")
logger.debug("User ID: \(userId, privacy: .private)")  // Release 빌드에서 마스킹됨
```

### 3.2 Release 빌드 로그 제거

```swift
// 로깅 유틸리티
enum Log {
    static func debug(_ message: String) {
        #if DEBUG
        print("[DEBUG] \(message)")
        #endif
    }
    
    static func error(_ message: String) {
        // 에러는 항상 기록하되 민감 정보 제외
        Logger().error("\(message)")
    }
}
```

---

## 4. 입력 검증 🟡 P1

### 4.1 SQL Injection 방지

```swift
// ❌ 잘못된 예 - 문자열 조합
let query = "SELECT * FROM users WHERE name = '\(userInput)'"

// ✅ 올바른 예 - Parameterized Query (SQLite)
let query = "SELECT * FROM users WHERE name = ?"
sqlite3_bind_text(statement, 1, userInput, -1, nil)
```

### 4.2 URL Scheme Injection

```swift
// ❌ 잘못된 예
func handleDeepLink(_ url: URL) {
    if let path = url.path {
        navigateTo(path)  // 검증 없이 사용
    }
}

// ✅ 올바른 예
func handleDeepLink(_ url: URL) {
    guard url.scheme == "myapp",
          let host = url.host,
          allowedHosts.contains(host) else {
        return
    }
    
    // 허용된 경로만 처리
    switch url.path {
    case "/profile":
        navigateToProfile()
    case "/settings":
        navigateToSettings()
    default:
        break
    }
}
```

---

## 5. 인증/인가 🔴 P0

### 5.1 토큰 관리

```swift
// ❌ 잘못된 예 - 토큰을 코드에 하드코딩
let apiKey = "sk-1234567890abcdef"

// ❌ 잘못된 예 - 토큰을 메모리에 평문 저장
class AuthManager {
    static var accessToken: String?  // 메모리 덤프에 노출 가능
}

// ✅ 올바른 예 - Keychain에서 필요할 때만 읽기
class AuthManager {
    func getAccessToken() -> String? {
        return KeychainHelper.read(key: "accessToken")
    }
    
    func clearTokens() {
        KeychainHelper.delete(key: "accessToken")
        KeychainHelper.delete(key: "refreshToken")
    }
}
```

### 5.2 생체 인증 🟡 P1

```swift
import LocalAuthentication

func authenticateWithBiometrics(completion: @escaping (Bool) -> Void) {
    let context = LAContext()
    var error: NSError?
    
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        completion(false)
        return
    }
    
    context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "앱 잠금 해제"
    ) { success, error in
        DispatchQueue.main.async {
            completion(success)
        }
    }
}
```

---

## 6. 데이터 보호 🟡 P1

### 6.1 File Protection

```swift
// ✅ 민감 파일에 보호 속성 적용
func saveSecureFile(data: Data, to url: URL) throws {
    try data.write(to: url, options: .completeFileProtection)
}

// Info.plist에서 기본 보호 수준 설정
// <key>NSFileProtectionComplete</key>
```

### 6.2 Clipboard 보안

```swift
// ❌ 잘못된 예 - 민감 정보를 클립보드에 복사
UIPasteboard.general.string = password

// ✅ 올바른 예 - 만료 시간 설정
let pasteboard = UIPasteboard.general
pasteboard.setItems([[UIPasteboard.typeAutomatic: sensitiveData]], 
                    options: [.expirationDate: Date().addingTimeInterval(60)])

// ✅ 또는 복사 기능 비활성화
textField.isSecureTextEntry = true
```

### 6.3 스크린샷/화면 녹화 방지 🟡 P1

```swift
// 민감 화면에서 스크린샷 방지
class SecureViewController: UIViewController {
    private var secureField: UITextField?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupScreenshotPrevention()
    }
    
    private func setupScreenshotPrevention() {
        let field = UITextField()
        field.isSecureTextEntry = true
        view.addSubview(field)
        field.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        field.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        view.layer.superlayer?.addSublayer(field.layer)
        field.layer.sublayers?.first?.addSublayer(view.layer)
        secureField = field
    }
}
```

---

## 7. 탈옥 감지 🟠 P2

```swift
class JailbreakDetector {
    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // 1. 탈옥 관련 파일 존재 확인
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        
        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // 2. 쓰기 권한 확인
        let testPath = "/private/jailbreak_test.txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
        #endif
    }
}
```

---

## 리뷰 체크리스트

### 🔴 P0 (즉시 수정)
- [ ] 민감 정보가 UserDefaults에 저장되지 않는지
- [ ] 토큰/비밀번호가 Keychain에 저장되는지
- [ ] HTTPS만 사용하는지
- [ ] 민감 정보가 로그에 출력되지 않는지
- [ ] 하드코딩된 API 키/시크릿이 없는지

### 🟡 P1 (출시 전 수정)
- [ ] Certificate Pinning 적용 여부
- [ ] 입력 검증 수행 여부
- [ ] File Protection 적용 여부
- [ ] 생체 인증 구현 시 적절한 fallback 여부
- [ ] 스크린샷 방지 필요 화면 처리 여부

### 🟠 P2 (권장)
- [ ] 탈옥 감지 구현 여부
- [ ] 디버거 감지 구현 여부
- [ ] 코드 난독화 적용 여부
