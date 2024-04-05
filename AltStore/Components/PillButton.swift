//
//  PillButton.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension PillButton
{
    static let minimumSize = CGSize(width: 77, height: 31)
    static let contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13)
}

final class PillButton: UIButton
{
    override var accessibilityValue: String? {
        get {
            guard self.progress != nil else { return super.accessibilityValue }
            return self.progressView.accessibilityValue
        }
        set { super.accessibilityValue = newValue }
    }
    
    var progress: Progress? {
        didSet {
            self.progressView.progress = Float(self.progress?.fractionCompleted ?? 0)
            self.progressView.observedProgress = self.progress
            
            let isUserInteractionEnabled = self.isUserInteractionEnabled
            self.isIndicatingActivity = (self.progress != nil)
            self.isUserInteractionEnabled = isUserInteractionEnabled
            
            self.update()
        }
    }
    
    var progressTintColor: UIColor? {
        get {
            return self.progressView.progressTintColor
        }
        set {
            self.progressView.progressTintColor = newValue
        }
    }
    
    var countdownDate: Date? {
        didSet {
            self.isEnabled = (self.countdownDate == nil)
            self.displayLink.isPaused = (self.countdownDate == nil)
            
            if self.countdownDate == nil
            {
                self.setTitle(nil, for: .disabled)
            }
        }
    }
    
    private let progressView = UIProgressView(progressViewStyle: .default)
    
    private lazy var displayLink: CADisplayLink = {
        let displayLink = CADisplayLink(target: self, selector: #selector(PillButton.updateCountdown))
        displayLink.preferredFramesPerSecond = 15
        displayLink.isPaused = true
        displayLink.add(to: .main, forMode: .common)
        return displayLink
    }()
    
    private let dateComponentsFormatter: DateComponentsFormatter = {
        let dateComponentsFormatter = DateComponentsFormatter()
        dateComponentsFormatter.zeroFormattingBehavior = [.pad]
        dateComponentsFormatter.collapsesLargestUnit = false
        return dateComponentsFormatter
    }()
    
    override var intrinsicContentSize: CGSize {
        let size = self.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
        return size
    }
    
    deinit
    {
        self.displayLink.remove(from: .main, forMode: RunLoop.Mode.default)
    }
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.layer.masksToBounds = true
        self.accessibilityTraits.formUnion([.updatesFrequently, .button])
        
        self.contentEdgeInsets = UIEdgeInsets(top: Self.contentInsets.top, left: Self.contentInsets.leading, bottom: Self.contentInsets.bottom, right: Self.contentInsets.trailing)
        
        self.activityIndicatorView.style = .medium
        self.activityIndicatorView.isUserInteractionEnabled = false
        
        self.progressView.progress = 0
        self.progressView.trackImage = UIImage()
        self.progressView.isUserInteractionEnabled = false
        self.addSubview(self.progressView)
        
        self.update()
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.progressView.bounds.size.width = self.bounds.width
        
        let scale = self.bounds.height / self.progressView.bounds.height
        
        self.progressView.transform = CGAffineTransform.identity.scaledBy(x: 1, y: scale)
        self.progressView.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        
        self.layer.cornerRadius = self.bounds.midY
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        self.update()
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize
    {
        var size = super.sizeThatFits(size)
        size.width = max(size.width, PillButton.minimumSize.width)
        size.height = max(size.height, PillButton.minimumSize.height)
        
        return size
    }
}

private extension PillButton
{
    func update()
    {
        if self.progress == nil
        {
            self.setTitleColor(.white, for: .normal)
            self.backgroundColor = self.tintColor
        }
        else
        {
            self.setTitleColor(self.tintColor, for: .normal)
            self.backgroundColor = self.tintColor.withAlphaComponent(0.15)
        }
        
        self.progressView.progressTintColor = self.tintColor
    }
    
    @objc func updateCountdown()
    {
        guard let endDate = self.countdownDate else { return }
        
        let startDate = Date()
        
        let interval = endDate.timeIntervalSince(startDate)
        guard interval > 0 else {
            self.isEnabled = true
            return
        }
        
        let text: String?
        
        if interval < (1 * 60 * 60)
        {
            self.dateComponentsFormatter.unitsStyle = .positional
            self.dateComponentsFormatter.allowedUnits = [.minute, .second]
            
            text = self.dateComponentsFormatter.string(from: startDate, to: endDate)
        }
        else if interval < (2 * 24 * 60 * 60)
        {
            self.dateComponentsFormatter.unitsStyle = .positional
            self.dateComponentsFormatter.allowedUnits = [.hour, .minute, .second]
            
            text = self.dateComponentsFormatter.string(from: startDate, to: endDate)
        }
        else
        {
            self.dateComponentsFormatter.unitsStyle = .full
            self.dateComponentsFormatter.allowedUnits = [.day]
            
            let numberOfDays = endDate.numberOfCalendarDays(since: startDate)
            text = String(format: NSLocalizedString("%@ DAYS", comment: ""), NSNumber(value: numberOfDays))
        }
        
        if let text = text
        {            
            UIView.performWithoutAnimation {
                self.isEnabled = false
                self.setTitle(text, for: .disabled)
                self.layoutIfNeeded()
            }
        }
        else
        {
            self.isEnabled = true
        }
    }
}
