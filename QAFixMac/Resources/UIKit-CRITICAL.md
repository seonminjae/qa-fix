# UIKit 치명적 결함 (CRITICAL) - 🔴 P0

이 문서는 UIKit 특화 치명적 결함을 다룹니다.

---

## 1. Delegate & Closure 🔴 P0

### 1.1 Delegate 순환 참조

**문제**: delegate를 strong으로 선언하면 메모리 누수

```swift
// ❌ 잘못된 예 - strong delegate
protocol UserDelegate: AnyObject {
    func userDidUpdate()
}

class UserManager {
    var delegate: UserDelegate?  // strong 참조
}

// ✅ 올바른 예 - weak delegate
class UserManager {
    weak var delegate: UserDelegate?  // weak 참조
}
```

### 1.2 Closure 캡처 리스트

```swift
// ❌ 잘못된 예 - self 강한 참조
class ViewController: UIViewController {
    var onComplete: (() -> Void)?
    
    func setup() {
        onComplete = {
            self.dismiss(animated: true)  // retain cycle
        }
    }
}

// ✅ 올바른 예 - weak self
class ViewController: UIViewController {
    var onComplete: (() -> Void)?
    
    func setup() {
        onComplete = { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}
```

---

## 2. 생명주기 관리 🔴 P0

### 2.1 viewDidLoad에서의 레이아웃

**문제**: viewDidLoad에서 frame 기반 레이아웃 시 잘못된 크기

```swift
// ❌ 잘못된 예 - viewDidLoad에서 frame 사용
override func viewDidLoad() {
    super.viewDidLoad()
    customView.frame = CGRect(
        x: 0, 
        y: 0, 
        width: view.bounds.width,  // 아직 정확하지 않을 수 있음
        height: 100
    )
}

// ✅ 올바른 예 - viewDidLayoutSubviews 또는 Auto Layout
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    customView.frame = CGRect(
        x: 0,
        y: 0,
        width: view.bounds.width,
        height: 100
    )
}

// ✅ 더 나은 방법 - Auto Layout
override func viewDidLoad() {
    super.viewDidLoad()
    customView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        customView.topAnchor.constraint(equalTo: view.topAnchor),
        customView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        customView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        customView.heightAnchor.constraint(equalToConstant: 100)
    ])
}
```

### 2.2 Observer/Notification 해제

```swift
// ❌ 잘못된 예 - Observer 미해제
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotification),
            name: .userDidLogin,
            object: nil
        )
        // deinit에서 해제 안 함
    }
}

// ✅ 올바른 예 - deinit에서 해제
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotification),
            name: .userDidLogin,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// ✅ 더 나은 방법 - Combine 사용
class ViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.publisher(for: .userDidLogin)
            .sink { [weak self] _ in
                self?.handleNotification()
            }
            .store(in: &cancellables)
    }
}
```

---

## 3. TableView/CollectionView 🔴 P0

### 3.1 Cell 재사용 문제

**문제**: prepareForReuse에서 상태 초기화 안 함

```swift
// ❌ 잘못된 예 - 상태 미초기화
class UserCell: UITableViewCell {
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    
    func configure(with user: User) {
        nameLabel.text = user.name
        // 이미지 로딩 후 셀이 재사용되면 잘못된 이미지 표시
        loadImage(url: user.imageURL)
    }
}

// ✅ 올바른 예 - prepareForReuse 구현
class UserCell: UITableViewCell {
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    private var imageTask: Task<Void, Never>?
    
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.image = nil
        nameLabel.text = nil
        imageTask?.cancel()
    }
    
    func configure(with user: User) {
        nameLabel.text = user.name
        imageTask = Task {
            profileImageView.image = await loadImage(url: user.imageURL)
        }
    }
}
```

### 3.2 Index Out of Bounds

```swift
// ❌ 잘못된 예 - 인덱스 검증 없음
func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let item = items[indexPath.row]  // 크래시 가능
    // ...
}

// ✅ 올바른 예 - 안전한 접근
func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let item = items[safe: indexPath.row]
    // ...
}
```

---

## 4. Navigation 🔴 P0

### 4.1 강제 캐스팅

```swift
// ❌ 잘못된 예 - 강제 캐스팅
override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    let vc = segue.destination as! DetailViewController
    vc.item = selectedItem
}

// ✅ 올바른 예 - 안전한 캐스팅
override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    guard segue.identifier == "showDetail",
          let vc = segue.destination as? DetailViewController else {
        return
    }
    vc.item = selectedItem
}
```

### 4.2 presentingViewController 참조

```swift
// ❌ 잘못된 예 - 강한 참조로 순환 참조 가능
class ModalViewController: UIViewController {
    var parentVC: UIViewController?  // strong 참조
}

// ✅ 올바른 예 - weak 참조 또는 delegate 패턴
class ModalViewController: UIViewController {
    weak var delegate: ModalDelegate?
    
    func dismiss() {
        delegate?.modalDidDismiss(self)
    }
}
```

---

## 5. Thread Safety 🔴 P0

### 5.1 UI 업데이트

```swift
// ❌ 잘못된 예 - 백그라운드에서 UI 업데이트
URLSession.shared.dataTask(with: url) { data, _, _ in
    self.label.text = "Loaded"  // 백그라운드 스레드
}.resume()

// ✅ 올바른 예 - 메인 스레드에서 UI 업데이트
URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
    DispatchQueue.main.async {
        self?.label.text = "Loaded"
    }
}.resume()
```

---

## 리뷰 체크리스트

- [ ] delegate가 weak으로 선언되었는지
- [ ] 클로저에서 [weak self] 사용
- [ ] NotificationCenter observer 해제
- [ ] prepareForReuse 구현
- [ ] 배열 인덱스 범위 검증
- [ ] 강제 캐스팅 사용 여부
- [ ] 메인 스레드에서 UI 업데이트
