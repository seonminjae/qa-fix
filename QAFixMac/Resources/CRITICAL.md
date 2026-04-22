# iOS 공통 치명적 결함 (CRITICAL) - 🔴 P0

이 문서는 앱 크래시, 메모리 누수, 데이터 손실을 유발할 수 있는 치명적 결함을 다룹니다.

---

## 1. 메모리 관리

### 1.1 Retain Cycle (순환 참조) 🔴 P0

**문제**: 클로저에서 `self`를 강하게 캡처하면 순환 참조로 메모리 누수 발생

```swift
// ❌ 잘못된 예
class ViewModel {
    var onComplete: (() -> Void)?
    
    func setup() {
        onComplete = {
            self.doSomething()  // strong capture
        }
    }
}

// ✅ 올바른 예
class ViewModel {
    var onComplete: (() -> Void)?
    
    func setup() {
        onComplete = { [weak self] in
            guard let self else { return }
            self.doSomething()
        }
    }
}
```

**체크리스트**:
- [ ] 클로저에서 `[weak self]` 또는 `[unowned self]` 사용
- [ ] delegate 프로퍼티가 `weak`으로 선언되었는지 확인
- [ ] NotificationCenter observer 해제 여부

### 1.2 강제 언래핑 (Force Unwrapping) 🔴 P0

**문제**: `!` 사용 시 nil이면 크래시 발생

```swift
// ❌ 잘못된 예
let user = response.data!
let name = user.name!

// ✅ 올바른 예 - guard let
guard let user = response.data,
      let name = user.name else {
    return
}

// ✅ 올바른 예 - if let
if let user = response.data {
    print(user.name ?? "Unknown")
}

// ✅ 올바른 예 - nil coalescing
let name = user.name ?? "Default"
```

**허용되는 예외**:
- `@IBOutlet` (스토리보드 연결 보장)
- 테스트 코드에서 명시적 실패 의도
- `fatalError`와 함께 사용하는 필수 초기화

### 1.3 강제 타입 캐스팅 (Force Casting) 🔴 P0

**문제**: `as!` 사용 시 타입이 맞지 않으면 크래시

```swift
// ❌ 잘못된 예
let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! CustomCell

// ✅ 올바른 예
guard let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as? CustomCell else {
    return UITableViewCell()
}
```

### 1.4 강제 try (Force Try) 🔴 P0

**문제**: `try!` 사용 시 에러 발생하면 크래시

```swift
// ❌ 잘못된 예
let data = try! JSONEncoder().encode(user)

// ✅ 올바른 예
do {
    let data = try JSONEncoder().encode(user)
} catch {
    print("Encoding failed: \(error)")
}

// ✅ 또는 optional try
let data = try? JSONEncoder().encode(user)
```

---

## 2. 동시성 (Concurrency)

### 2.1 Data Race 🔴 P0

**문제**: 여러 스레드에서 동시에 mutable 데이터 접근

```swift
// ❌ 잘못된 예
class Counter {
    var count = 0
    
    func increment() {
        count += 1  // Data race 가능
    }
}

// ✅ 올바른 예 - Actor 사용 (Swift 5.5+)
actor Counter {
    var count = 0
    
    func increment() {
        count += 1
    }
}

// ✅ 올바른 예 - 직렬 큐 사용
class Counter {
    private var count = 0
    private let queue = DispatchQueue(label: "counter.queue")
    
    func increment() {
        queue.sync {
            count += 1
        }
    }
}
```

### 2.2 UI 업데이트 스레드 🔴 P0

**문제**: 메인 스레드가 아닌 곳에서 UI 업데이트

```swift
// ❌ 잘못된 예
URLSession.shared.dataTask(with: url) { data, _, _ in
    self.label.text = "Updated"  // 백그라운드 스레드에서 UI 업데이트
}.resume()

// ✅ 올바른 예 - DispatchQueue
URLSession.shared.dataTask(with: url) { data, _, _ in
    DispatchQueue.main.async {
        self.label.text = "Updated"
    }
}.resume()

// ✅ 올바른 예 - @MainActor (Swift 5.5+)
@MainActor
func updateUI(text: String) {
    label.text = text
}
```

### 2.3 Async/Await Task 취소 🔴 P0

**문제**: Task 취소 미처리로 불필요한 작업 수행 또는 크래시

```swift
// ❌ 잘못된 예
func fetchData() async {
    let data = await api.fetch()
    self.data = data  // Task 취소되어도 실행됨
}

// ✅ 올바른 예
func fetchData() async throws {
    let data = try await api.fetch()
    try Task.checkCancellation()
    await MainActor.run {
        self.data = data
    }
}
```

---

## 3. 생명주기 (Lifecycle)

### 3.1 Deinit에서의 비동기 작업 🔴 P0

**문제**: `deinit`에서 비동기 작업 수행 시 예측 불가능한 동작

```swift
// ❌ 잘못된 예
deinit {
    DispatchQueue.main.async {
        self.cleanup()  // self가 이미 해제됨
    }
}

// ✅ 올바른 예
deinit {
    NotificationCenter.default.removeObserver(self)
    timer?.invalidate()
    // 동기 작업만 수행
}
```

### 3.2 Timer/Observer 미해제 🔴 P0

**문제**: Timer나 Observer를 해제하지 않으면 메모리 누수

```swift
// ❌ 잘못된 예
class ViewModel {
    var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.update()
        }
    }
    // deinit에서 해제 안 함
}

// ✅ 올바른 예
class ViewModel {
    var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.update()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

---

## 4. Combine

### 4.1 AnyCancellable 미저장 🔴 P0

**문제**: Cancellable을 저장하지 않으면 즉시 구독 해제

```swift
// ❌ 잘못된 예
func subscribe() {
    publisher.sink { value in
        print(value)
    }
    // Cancellable이 저장되지 않아 즉시 해제됨
}

// ✅ 올바른 예
private var cancellables = Set<AnyCancellable>()

func subscribe() {
    publisher
        .sink { value in
            print(value)
        }
        .store(in: &cancellables)
}
```

### 4.2 Combine에서의 Retain Cycle 🔴 P0

```swift
// ❌ 잘못된 예
viewModel.$state
    .sink { state in
        self.updateUI(state)  // strong capture
    }
    .store(in: &cancellables)

// ✅ 올바른 예
viewModel.$state
    .sink { [weak self] state in
        self?.updateUI(state)
    }
    .store(in: &cancellables)
```

---

## 5. 초기화 (Initialization)

### 5.1 Required Init 누락 🔴 P0

**문제**: `NSCoding` 프로토콜의 required init 누락

```swift
// ❌ 잘못된 예
class CustomView: UIView {
    init(customParam: String) {
        super.init(frame: .zero)
    }
    // required init?(coder:) 누락 - 컴파일 에러
}

// ✅ 올바른 예
class CustomView: UIView {
    init(customParam: String) {
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

### 5.2 Implicitly Unwrapped Optional 남용 🔴 P0

**문제**: `!`로 선언된 프로퍼티 초기화 전 접근 시 크래시

```swift
// ❌ 잘못된 예
class ViewController: UIViewController {
    var viewModel: ViewModel!  // 초기화 전 접근 시 크래시
}

// ✅ 올바른 예 - lazy
class ViewController: UIViewController {
    lazy var viewModel = ViewModel()
}

// ✅ 올바른 예 - DI
class ViewController: UIViewController {
    let viewModel: ViewModel
    
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
}
```

---

## 리뷰 체크리스트

- [ ] 강제 언래핑 (`!`) 사용 여부
- [ ] 강제 캐스팅 (`as!`) 사용 여부
- [ ] 강제 try (`try!`) 사용 여부
- [ ] 클로저에서 `[weak self]` 사용 여부
- [ ] delegate가 `weak`으로 선언되었는지
- [ ] Timer/Observer 해제 여부
- [ ] Combine Cancellable 저장 여부
- [ ] 메인 스레드에서 UI 업데이트 여부
- [ ] Data Race 가능성
- [ ] Task 취소 처리 여부
