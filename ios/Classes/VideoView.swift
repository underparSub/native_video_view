// 시작점7 (remove cached Image)
//  VideoView.swift
//  native_video_view
//
//  Created by Luis Jara Castillo on 11/4/19.
//

import UIKit
import AVFoundation


class VideoView : UIView {
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoAsset: AVAsset?
    private var initialized: Bool = false
    private var onPrepared: (()-> Void)? = nil
    private var onFailed: ((String) -> Void)? = nil
    private var onCompletion: (() -> Void)? = nil
    private var videoPath: String?
    private var videoSize: CGSize = CGSize.zero
    private var imageProcessingWorkItem: DispatchWorkItem?
    private var throttlingWorkItem: DispatchWorkItem?
//    private let imageCache = NSCache<NSString, UIImage>()
    private var generator: AVAssetImageGenerator?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var context: CIContext?
    private lazy var magnifiedImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = UIColor.black
        imageView.contentMode = .scaleAspectFill
        imageView.layer.masksToBounds  = true
        return imageView
    }()
    private lazy var magnifiedView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderColor = UIColor.white.cgColor
        view.layer.borderWidth = 1.0
        view.layer.masksToBounds =  true
        view.layer.cornerRadius = 50
        return view
    }()
    private lazy var centerCircle: UIView =  {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints  = false
        view.layer.borderColor = UIColor(r: 183, g: 28, b: 28).cgColor
        view.layer.borderWidth = 3.0
        view.layer.masksToBounds =  true
        view.layer.cornerRadius = 24 / 2
        return view
    }()
    
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
    }
    
    deinit {
        self.removeOnFailedObserver()
        self.removeOnPreparedObserver()
        self.removeOnCompletionObserver()
        self.player?.removeObserver(self, forKeyPath: "status")
        NotificationCenter.default.removeObserver(self)
        self.stop()
        self.initialized = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.configureVideoLayer()
        self.configureMagnifier()
    }
    
//    private func cacheImage(_ image: UIImage, for time: CMTime) {
//        let timeKey = NSString(string: "\(self.videoPath ?? ""):\(time.value)")
//        imageCache.setObject(image, forKey: timeKey)
//    }
//
//    private func cachedImage(for time: CMTime) -> UIImage? {
//        let timeKey = NSString(string: "\(self.videoPath ?? ""):\(time.value)")
//        return imageCache.object(forKey: timeKey)
//    }
//
//
    
    func configure(videoPath: String?, isURL: Bool){
        if !initialized {
            self.initVideoPlayer()
        }
        if let path = videoPath {
            self.videoPath = path
            let uri: URL? = isURL ? URL(string: path) : URL(fileURLWithPath: path)
            let asset = AVAsset(url: uri!)
            self.videoSize = getVideoSize(from: uri!) ?? CGSize.zero
            player?.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            self.playerItem = player?.currentItem
            let pixelBufferAttributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
            self.playerItem?.add(videoOutput!)
            self.context = CIContext()
            self.videoAsset = asset
            guard let assetTrack = asset.tracks(withMediaType: .video).first else { return }
            self.generator = AVAssetImageGenerator(asset: asset)
            self.generator?.requestedTimeToleranceBefore = .zero
            self.generator?.requestedTimeToleranceAfter = .zero
            self.generator?.appliesPreferredTrackTransform = true
            self.generator?.maximumSize = assetTrack.naturalSize
            self.configureVideoLayer()
            NotificationCenter.default.addObserver(self, selector: #selector(onVideoCompleted(notification:)), name: .AVPlayerItemDidPlayToEndTime, object: self.player?.currentItem)
        }
    }
    
    private func configureVideoLayer(){
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = bounds
        playerLayer?.videoGravity = .resizeAspect
        if let playerLayer = self.playerLayer {
            self.clearSubLayers()
            layer.addSublayer(playerLayer)
        }
    }
    
    private func configureMagnifier() {
        self.clearMagnifier()
        self.addSubview(magnifiedView)
        magnifiedView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        magnifiedView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        magnifiedView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        magnifiedView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        
        self.magnifiedView.addSubview(magnifiedImageView)
        magnifiedImageView.centerYAnchor.constraint(equalTo: magnifiedView.centerYAnchor).isActive = true
        magnifiedImageView.centerXAnchor.constraint(equalTo: magnifiedView.centerXAnchor).isActive = true
        magnifiedImageView.heightAnchor.constraint(equalToConstant: self.frame.size.height).isActive = true
        magnifiedImageView.widthAnchor.constraint(equalToConstant: self.frame.size.width).isActive = true
        
        
        self.magnifiedImageView.addSubview(centerCircle)
        centerCircle.centerYAnchor.constraint(equalTo: magnifiedImageView.centerYAnchor).isActive = true
        centerCircle.centerXAnchor.constraint(equalTo: magnifiedImageView.centerXAnchor).isActive = true
        centerCircle.heightAnchor.constraint(equalToConstant: 24).isActive = true
        centerCircle.widthAnchor.constraint(equalToConstant: 24).isActive = true
        magnifiedView.isHidden = true
        
    }
    private func clearMagnifier() {
        self.subviews.forEach{
            $0.removeFromSuperview()
        }
    }
    
    
    private func clearSubLayers(){
        layer.sublayers?.forEach{
            $0.removeFromSuperlayer()
        }
    }
    
    private func initVideoPlayer(){
        self.player = AVPlayer(playerItem: nil)
        self.player?.addObserver(self, forKeyPath: "status", options: [], context: nil)
        self.initialized = true
    }
    
    func play(){
        if !self.isPlaying() && self.videoAsset != nil {
            self.player?.play()
        }
    }
    
    
    func onPanEnd() {
        imageProcessingWorkItem?.cancel()
        fadeAnimation(isShow: false)
    }
    
    func fadeAnimation(isShow: Bool) {
        UIView.animate(withDuration: 0.3, animations: {
            self.magnifiedView.alpha = isShow ? 1: 0
        }, completion: {
            finished in
            self.magnifiedView.isHidden =  (isShow  && self.imageProcessingWorkItem?.isCancelled == false  ) ? false : true
        })

    }
    
    
    func onPanUpdate(position: [Double]) {
        let panLocation: CGPoint = CGPoint(x: position[0], y: position[1])
        guard let player = player else { return }
        let time = player.currentTime()
        let vw = self.videoSize.width
        let vh = self.videoSize.height
        let vRatio = vw / vh;
        let viewerWidth = self.frame.width
        let viewerHeight = self.frame.height
        let  viewerRatio = viewerWidth / viewerHeight;
        var height = viewerHeight;
        var width = viewerHeight / vh * vw;
        if (vRatio >= viewerRatio) {
            height = viewerWidth / vw * vh;
            width = viewerWidth;
        }
        
        imageProcessingWorkItem = DispatchWorkItem { [weak self] in
            guard let pixelBuffer = self?.videoOutput?.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
                return
            }
            let baseImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = self?.context?.createCGImage(baseImage, from: baseImage.extent) else { return }
            let newImage = UIImage(cgImage: cgImage)
            let targetSize = CGSize(width: width, height: height)
            let widthRatio  = targetSize.width  / newImage.size.width
            let heightRatio = targetSize.height / newImage.size.height
            let ratio = min(widthRatio, heightRatio)
            let newSize = CGSize(width: newImage.size.width * ratio, height: newImage.size.height * ratio)
            let rect = CGRect(x: -panLocation.x + viewerWidth / 2 , y: -panLocation.y + viewerHeight / 2, width: newSize.width, height: newSize.height)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let image = renderer.image { ctx in
                newImage.draw(in: rect)
            }
            if self?.imageProcessingWorkItem?.isCancelled == false {
                DispatchQueue.main.async {
                    self?.magnifiedImageView.image = image
                    self?.magnifiedView.center = CGPoint(x: panLocation.x - 50, y: panLocation.y - 50)
                    self?.fadeAnimation(isShow: true)
                }
            } else {
                DispatchQueue.main.async {
                    self?.magnifiedView.isHidden = true
                }
            }
        }
        if let imageProcessingWorkItem = imageProcessingWorkItem  {
            DispatchQueue.global(qos: .userInteractive).async(execute: imageProcessingWorkItem)
        }
        
    }
    
   
    
    func pause(restart:Bool){
        self.player?.pause()
        if(restart){
            self.player?.seek(to: CMTime.zero)
        }
    }
    
    func stop(){
        self.pause(restart: true)
    }
    
    func isPlaying() -> Bool{
        return self.player?.rate != 0 && self.player?.error == nil
    }
    
    func setVolume(volume:Double){
        self.player?.volume = Float(volume)
    }
    
    func getDuration()-> Int64 {
        let durationObj = self.player?.currentItem?.asset.duration
        return self.transformCMTime(time: durationObj)
    }
    
    func getCurrentPosition() -> Int64 {
        let currentTime = self.player?.currentItem?.currentTime()
        return self.transformCMTime(time: currentTime)
    }
    
    func getVideoSize(from videoUrl: URL) -> CGSize? {
        let asset = AVURLAsset(url: videoUrl)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
    
    
    func getVideoHeight() -> Double {
        var height: Double = 0.0
        let videoTrack = self.getVideoTrack()
        if videoTrack != nil {
            height = Double(videoTrack?.naturalSize.height ?? 0.0)
        }
        return height
    }
    
    func getVideoWidth() -> Double {
        var width: Double = 0.0
        let videoTrack = self.getVideoTrack()
        if videoTrack != nil {
            width = Double(videoTrack?.naturalSize.width ?? 0.0)
        }
        return width
    }
    
    func getVideoTrack() -> AVAssetTrack? {
        var videoTrack: AVAssetTrack? = nil
        let tracks = videoAsset?.tracks(withMediaType: .video)
        if tracks != nil && tracks!.count > 0 {
            videoTrack = tracks![0]
        }
        return videoTrack
    }
    
    private func transformCMTime(time:CMTime?) -> Int64 {
        var ts : Double = 0
        if let obj = time {
            ts = CMTimeGetSeconds(obj) * 1000
        }
        return Int64(ts)
    }
    
    func seekTo(positionInMillis: Int64?){
        if let pos = positionInMillis {
            self.player?.seek(to: CMTimeMake(value: pos, timescale: 1000), toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        }
    }
    
    func addOnPreparedObserver(callback: @escaping ()->Void){
        self.onPrepared = callback
    }
    
    func removeOnPreparedObserver() {
        self.onPrepared = nil
    }
    
    private func notifyOnPreaparedObserver(){
        if onPrepared != nil {
            self.onPrepared!()
        }
    }
    
    func addOnFailedObserver(callback: @escaping (String)->Void){
        self.onFailed = callback
    }
    
    func removeOnFailedObserver() {
        self.onFailed = nil
    }
    
    private func notifyOnFailedObserver(message: String){
        if onFailed != nil {
            self.onFailed!(message)
        }
    }
    
    func addOnCompletionObserver(callback: @escaping ()->Void){
        self.onCompletion = callback
    }
    
    func removeOnCompletionObserver() {
        self.onCompletion = nil
    }
    
    private func notifyOnCompletionObserver(){
        if onCompletion != nil {
            self.onCompletion!()
        }
    }
    
    @objc func onVideoCompleted(notification:NSNotification){
        self.notifyOnCompletionObserver()
    }
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            let status = self.player!.status
            switch(status){
            case .unknown:
                print("Status unknown")
                break
            case .readyToPlay:
                self.notifyOnPreaparedObserver()
                break
            case .failed:
                if let error = self.player?.error{
                    let errorMessage = error.localizedDescription
                    self.notifyOnFailedObserver(message: errorMessage)
                }
                break
            default:
                print("Status unknown")
                break
            }
        }
    }
}



extension AVPlayerItem {
    var url: URL? {
        return (asset as? AVURLAsset)?.url
    }
}

extension UIColor {
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.init(red: r/255, green: g/255, blue: b/255, alpha: 1)
    }
}






