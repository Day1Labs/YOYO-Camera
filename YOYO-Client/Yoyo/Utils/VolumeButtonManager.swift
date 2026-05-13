import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// volume button listener manager
/// observesystemvolumevolume, used fortriggertake a photo
final class VolumeButtonManager: NSObject, ObservableObject {
    // MARK: - Properties

    /// Singleton instance
    static let shared = VolumeButtonManager()

    /// systemvolume
    private var systemVolumeValue: Float = 0.5
    /// systemvolumewhetherinitialization
    private var filledSystemVolumeValue = false
    /// whetherneed to restoresystemvolume
    private var needRecoverSystemVolumeValue = false
    /// , used fortimermanagement
    private var timeIndex: Int = 0
    /// whetherin progressvolume
    private var touching = false
    /// whetherautorestorevolume
    private var isAutoRecover = false
    /// whetherautorestorevolume
    private var isAutoRecoverImmediately = false
    /// whether
    private var lastIsBelow = false
    /// whether
    private var lastAct = false
    /// temporaryvolume
    private var lastTmpVolumeValue: Float = 0.0
    /// whethersystemvolumenotify
    private var existingSystemVolumeNotification = false
    /// whethersystemvolumeobserve
    private var hasRegisteredSystemVolume = false
    /// whetherin progressobserve
    private var isMonitoring = false
    /// whethersetvolumeobserve
    private var hasSetupVolumeMonitoring = false

    /// volumeview
    private static var volumeView: MPVolumeView = {
        let view = MPVolumeView(
            frame: CGRect(x: -1000, y: -1000, width: 1, height: 1)
        )
        view.showsVolumeSlider = true
        view.isHidden = false
        view.alpha = 0.01
        view.clipsToBounds = true

        // iOS 13+ showsRouteButton, compatibilityset
        if #available(iOS 13.0, *) {
            // not use API
        } else {
            view.showsRouteButton = false
        }

        return view
    }()

    /// volumeviewwhetheradd
    private static var volumeViewAddedToWindow = false

    /// volumecallback
    var onVolumeButtonPressed: (() -> Void)?
    /// volumestatecallback (isDown, volume, touching)
    var onVolumeStatusChanged: ((Bool, Float, Bool) -> Void)?

    // MARK: - Volume Monitoring Setup

    /// setvolumeobserve
    private func setupVolumeMonitoring() {
        guard !hasSetupVolumeMonitoring else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(volumeChanged(_:)),
            name: NSNotification.Name("SystemVolumeDidChange"),
            object: nil
        )

        hasSetupVolumeMonitoring = true
    }

    /// removevolumeobserve
    private func removeVolumeMonitoring() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("SystemVolumeDidChange"),
            object: nil
        )

        if #available(iOS 16.4, *), !existingSystemVolumeNotification {
            if hasRegisteredSystemVolume {
                do {
                    try AVAudioSession
                        .sharedInstance()
                        .removeObserver(self, forKeyPath: "outputVolume")
                    hasRegisteredSystemVolume = false
                } catch {
                    print("移除KVO监听失败: \(error)")
                }
            }
        }
    }

    // MARK: - Lifecycle

    override private init() {
        super.init()
        checkSystemVersionCompatibility()
    }

    deinit {
        stopMonitoring()
        if hasSetupVolumeMonitoring {
            removeVolumeMonitoring()
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    /// checksystemcompatibility
    private func checkSystemVersionCompatibility() {
        if #available(iOS 16.4.1, *) {
            existingSystemVolumeNotification = true
        } else if #available(iOS 16.4, *) {
            existingSystemVolumeNotification = false
        } else {
            existingSystemVolumeNotification = true
        }
    }

    /// setvolumeview
    private func setupVolumeView() {
        // ensure MPVolumeView addsystemvolume HUD
        Self.ensureVolumeViewInWindow()
        Self.setVolumeViewHidden(true)
    }

    /// ensurevolumeviewadd
    private static func ensureVolumeViewInWindow() {
        guard !volumeViewAddedToWindow else { return }

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first
            {
                // remove(if)
                volumeView.removeFromSuperview()

                // add
                window.addSubview(volumeView)
                volumeView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
                volumeView.alpha = 0.01
                volumeView.layer.zPosition = -1000
                volumeViewAddedToWindow = true
                print("MPVolumeView 已添加到窗口以隐藏系统音量 HUD")
            }
        }
    }

    // MARK: - Public Methods

    /// startobservevolume
    func startMonitoring() {
        guard !isMonitoring else { return }

        setupVolumeView()
        setupVolumeMonitoring()
        configureAudioSession()
        isMonitoring = true
        print("音量键监听已启动")
    }

    /// stopobservevolume
    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        removeVolumeMonitoring()
        hasSetupVolumeMonitoring = false
        filledSystemVolumeValue = false // resetinitialization, ensuresyncsystemvolume
        print("音量键监听已停止")
    }

    /// getcurrentsystemvolume
    func getCurrentSystemVolume() -> Float {
        for subview in Self.volumeView.subviews {
            if let slider = subview as? UISlider {
                return slider.value
            }
        }
        return 0.5
    }

    /// updatesystemvolume
    func updateSystemVolumeValue() {
        systemVolumeValue = getCurrentSystemVolume()
        print("更新音量基准值: \(systemVolumeValue)")
    }

    // MARK: - Private Methods

    /// configureaudiosession
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // ✅ key: not camera/recordingin progressuseaudio.ambient
            // camera(videomode)use.playAndRecord; here AVCaptureSession runtime error,
            // preview(sampleBuffer not thencallback).
            if audioSession.category == .playAndRecord {
                print("⚠️ [VolumeButtonManager] Skip configuring AudioSession (.ambient) because current category is .playAndRecord")
                return
            }

            // use.ambient, this waynot audio
            // volumeobserve, onlyneed to volume, not need to recordingaudio
            try audioSession.setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )

            try audioSession.setActive(true)
            print("音频会话配置成功（ambient模式，不中断背景音频）")
        } catch {
            print("配置音频会话失败: \(error.localizedDescription)")
        }
    }

    /// setsystemvolume
    private func updateSystemMusicPlayerVolume(
        _ volume: Float,
        autoRecover: Bool,
        immediately: Bool
    ) {
        print(
            "真实修改音量: \(volume), auto: \(autoRecover), immediately: \(immediately)"
        )

        for subview in Self.volumeView.subviews {
            if let slider = subview as? UISlider {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    if autoRecover, slider.value != volume {
                        self.isAutoRecover = true
                    }
                    if immediately {
                        self.isAutoRecoverImmediately = true
                    }
                    slider.value = volume
                }
                break
            }
        }
    }

    /// volume
    private func fixedMusicPlayerVolume(_ nextVolume: Float) -> Float {
        var playerVolume = systemVolumeValue

        if #available(iOS 16.4, *), !existingSystemVolumeNotification {
            // systemvolumemaximumbuttonvolume, not volume0
            if systemVolumeValue == 0,
               nextVolume >= lastTmpVolumeValue || lastTmpVolumeValue == 1.0
            {
                playerVolume = nextVolume
            }
        }

        return playerVolume
    }

    /// volumestate
    @discardableResult
    private func handleVolumeStatusChange(_ isDown: Bool) -> Bool {
        var hasAction = false

        if isDown != touching {
            touching = isDown
        } else {
            return hasAction
        }

        // triggerstatecallback
        onVolumeStatusChanged?(isDown, systemVolumeValue, touching)

        // ifstate, triggertake a photocallback
        if isDown {
            onVolumeButtonPressed?()
            hasAction = true
        }

        print("音量键当前状态: \(isDown ? "被按下" : "已松手"), action: \(hasAction)")
        return hasAction
    }

    /// volumebuttontimerupdate
    @objc private func volumeButtonTimerUpdate(_ updateTimeIndex: NSNumber) {
        print(
            "音量改变定时器触发: \(systemVolumeValue), recover: \(needRecoverSystemVolumeValue)"
        )

        if updateTimeIndex.intValue != timeIndex {
            print("定时器序号已变更: \(updateTimeIndex.intValue) vs \(timeIndex)")
            return
        }

        if isAutoRecoverImmediately, abs(lastTmpVolumeValue - systemVolumeValue) < 0.01 {
            isAutoRecoverImmediately = false
        }

        handleVolumeStatusChange(false)

        if needRecoverSystemVolumeValue {
            let playerVolume = fixedMusicPlayerVolume(
                AVAudioSession.sharedInstance().outputVolume
            )
            updateSystemMusicPlayerVolume(
                playerVolume,
                autoRecover: true,
                immediately: false
            )
            needRecoverSystemVolumeValue = false
            print("属于回滚: \(systemVolumeValue)")
        } else {
            print("不属于回滚: \(systemVolumeValue)")
        }
    }

    // MARK: - Notification Handlers

    @objc private func didBecomeActive() {
        print("重新激活: \(getCurrentSystemVolume())")
        systemVolumeValue = getCurrentSystemVolume()

        // ifin progressobserve, configureaudiosessionensureuse.ambient
        // , because(AudioSessionManager)can audiosession
        if isMonitoring {
            configureAudioSession()
        }

        if #available(iOS 16.4, *) {
            if !existingSystemVolumeNotification {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    do {
                        try AVAudioSession.sharedInstance().addObserver(
                            self,
                            forKeyPath: "outputVolume",
                            options: .new,
                            context: nil
                        )

                        if !self.hasRegisteredSystemVolume {
                            self.hasRegisteredSystemVolume = true
                        }
                    } catch {
                        print("添加KVO监听失败: \(error)")
                    }
                }
            }
        }
    }

    @objc private func willResignActive() {
        if #available(iOS 16.4, *), !existingSystemVolumeNotification {
            if hasRegisteredSystemVolume {
                do {
                    try AVAudioSession
                        .sharedInstance()
                        .removeObserver(self, forKeyPath: "outputVolume")
                    hasRegisteredSystemVolume = false
                } catch {
                    print("移除KVO监听失败: \(error)")
                }
            }
        }
    }

    @objc private func volumeChanged(_ notification: Notification) {
        guard isMonitoring else { return }

        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.volumeChanged(notification)
            }
            return
        }

        guard let userInfo = notification.userInfo else { return }

        // print("volume: \(userInfo)")

        // getvolume
        var volumeKey = "AudioVolume"
        var reasonKey = "AudioVolumeChangeReason"

        if #available(iOS 15, *) {
            volumeKey = "Volume"
            reasonKey = "Reason"
        }

        guard let nextVolume = userInfo[volumeKey] as? Float,
              let reason = userInfo[reasonKey] as? String else { return }

        // checkwhethersystemvolumenotify
        if reason == "ExplicitVolumeChange",
           userInfo["Source"] as? String == "outputVolume",
           existingSystemVolumeNotification
        {
            return
        }

        if reason == "ExplicitVolumeChange", userInfo["SequenceNumber"] != nil {
            existingSystemVolumeNotification = true
        }

        // print(
        // 	"volume: \(nextVolume) (\(reason)), touching: \(touching), auto: \(isAutoRecover), im: \(isAutoRecoverImmediately)"
        // )

        // initializationsystemvolume
        if !filledSystemVolumeValue {
            print("系统音量初始化: \(nextVolume)")
            systemVolumeValue = nextVolume
            updateSystemMusicPlayerVolume(
                nextVolume,
                autoRecover: false,
                immediately: false
            )
            filledSystemVolumeValue = true
            return // ⚠️ initializationnotifyonlyused forsyncstate, not triggertake a photo
        }

        // checkwhetherstate
        guard UIApplication.shared.applicationState == .active else { return }

        // volumeorientation
        var isBelow = nextVolume <= systemVolumeValue
        if nextVolume == systemVolumeValue {
            if isAutoRecover || isAutoRecoverImmediately {
                isBelow = lastIsBelow
            } else if nextVolume == 1, systemVolumeValue == 1 {
                isBelow = false
            }
        }

        var anyAct = false
        let isDown = false

        if reason == "ExplicitVolumeChange" {
            // timer
            NSObject
                .cancelPreviousPerformRequests(
                    withTarget: self,
                    selector: #selector(volumeButtonTimerUpdate(_:)),
                    object: NSNumber(value: timeIndex)
                )

            if isAutoRecover {
                print("回滚触发")
                isAutoRecover = false
                return
            } else if !touching, isAutoRecoverImmediately, abs(nextVolume - systemVolumeValue) < 0.01 {
                print("立即回滚触发")
                isAutoRecoverImmediately = false
                needRecoverSystemVolumeValue = false
                return
            } else {
                lastIsBelow = isBelow
                timeIndex += 1
                let currentTimeIndex = timeIndex

                if !touching {
                    print("启动定时器1, timeIndex: \(currentTimeIndex)")
                    perform(
                        #selector(volumeButtonTimerUpdate(_:)),
                        with: NSNumber(value: currentTimeIndex),
                        afterDelay: 1.0
                    )
                    anyAct = handleVolumeStatusChange(true)
                    lastAct = anyAct
                    needRecoverSystemVolumeValue = needRecoverSystemVolumeValue || anyAct

                    if !anyAct {
                        print("更新当前音量值: \(nextVolume)")
                        systemVolumeValue = nextVolume
                    } else {
                        let playerVolume = fixedMusicPlayerVolume(nextVolume)
                        updateSystemMusicPlayerVolume(
                            playerVolume,
                            autoRecover: false,
                            immediately: true
                        )
                    }
                } else {
                    if lastAct {
                        let playerVolume = fixedMusicPlayerVolume(nextVolume)
                        updateSystemMusicPlayerVolume(
                            playerVolume,
                            autoRecover: false,
                            immediately: true
                        )
                    }
                    print("启动定时器2, timeIndex: \(currentTimeIndex)")
                    perform(
                        #selector(volumeButtonTimerUpdate(_:)),
                        with: NSNumber(value: currentTimeIndex),
                        afterDelay: 0.4
                    )
                }
            }

            print(
                "回滚状态: \(needRecoverSystemVolumeValue), volume: \(systemVolumeValue)"
            )
        } else if reason == "RouteChange" {
            if #available(iOS 13.0, *) {
                if touching {
                    print("RouteChange return")
                    return
                }
            }
            // print("timer, timeIndex: \(timeIndex)")
            NSObject
                .cancelPreviousPerformRequests(
                    withTarget: self,
                    selector: #selector(volumeButtonTimerUpdate(_:)),
                    object: NSNumber(value: timeIndex)
                )
        }

        // print(
        // 	"volume: \(nextVolume)(\(systemVolumeValue)), touch: \(touching), isDown: \(isDown), revert: \(reason == "ExplicitVolumeChange"), ret: \(needRecoverSystemVolumeValue), below: \(isBelow)"
        // )

        if touching {
            onVolumeStatusChanged?(isBelow, systemVolumeValue, touching)
        }

        lastTmpVolumeValue = nextVolume
    }

    // MARK: - KVO

    override func observeValue(
        forKeyPath keyPath: String?,
        of _: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context _: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "outputVolume" else { return }

        if #available(iOS 16.4, *), !existingSystemVolumeNotification {
            guard let change,
                  let newValue = change[.newKey] as? Float else { return }

            let userInfo = [
                "Reason": "ExplicitVolumeChange",
                "Volume": newValue,
                "Source": "outputVolume",
            ] as [String: Any]

            print("KVO音量改变, outputVolume变为: \(newValue)")

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SystemVolumeDidChange"),
                    object: nil,
                    userInfo: userInfo
                )
            }
        }
    }

    // MARK: - Static Methods

    /// setvolumeviewstate
    /// - Parameter isHidden: true = systemvolume HUD(MPVolumeView can); false = systemvolume HUD(MPVolumeView)
    static func setVolumeViewHidden(_ isHidden: Bool) {
        print("音量键真实状态: \(isHidden ? "隐藏系统HUD" : "显示系统HUD")")
        DispatchQueue.main.async {
            // ensure volumeView
            ensureVolumeViewInWindow()

            if isHidden {
                // systemvolume HUD: MPVolumeView view isHidden = false
                // set, isHidden = false
                volumeView.isHidden = false
                volumeView.alpha = 0.01
                volumeView.frame = CGRect(
                    x: -1000,
                    y: -1000,
                    width: 1,
                    height: 1
                )
                NotificationCenter.default
                    .post(
                        name: NSNotification
                            .Name("SetVolumeViewHiddenNotification"),
                        object: nil
                    )
            } else {
                // systemvolume HUD: MPVolumeView
                volumeView.isHidden = true
                NotificationCenter.default
                    .post(
                        name: NSNotification
                            .Name("SetVolumeViewShownNotification"),
                        object: nil
                    )
            }
        }
    }

    /// volumeview
    /// - Parameter show: true = systemvolume HUD; false = systemvolume HUD
    static func showVolumeView(_ show: Bool) {
        print("音量键真实状态B: \(!show ? "隐藏系统HUD" : "显示系统HUD")")
        DispatchQueue.main.async {
            if show {
                // systemvolume HUD: remove MPVolumeView
                volumeView.removeFromSuperview()
                volumeViewAddedToWindow = false
            } else {
                // systemvolume HUD: ensure MPVolumeView
                ensureVolumeViewInWindow()
                volumeView.isHidden = false
                volumeView.alpha = 0.01
            }
        }
    }
}
