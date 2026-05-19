//
// Copyright NetFoundry Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Cocoa

class GettingStartedViewController: NSViewController {

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 460))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 500, height: 460)
        setupUI()
    }

    private func setupUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 30, bottom: 20, right: 30)

        // Logo on white card
        stack.addArrangedSubview(makeLogoCard())

        // Welcome heading
        let heading = makeLabel("Welcome to Ziti Desktop Edge",
                                font: .boldSystemFont(ofSize: 18))
        heading.alignment = .center
        stack.addArrangedSubview(heading)

        // Separator
        let sep = NSBox()
        sep.boxType = .separator
        stack.addArrangedSubview(sep)

        // Deploy a Network section
        stack.addArrangedSubview(makeSection(
            title: "Deploy a Network",
            body: "New to OpenZiti? Get started by deploying your own zero trust network overlay.",
            linkTitle: "Learn how to deploy a network",
            url: "https://netfoundry.io/docs/openziti/#deploy_an_overlay"))

        // Already have a network section
        stack.addArrangedSubview(makeSection(
            title: "Already have a network?",
            body: "Use the \"+\" button at the bottom of the identity list to add an identity. Your network admin can provide an enrollment JWT file or an enrollment URL.",
            linkTitle: nil,
            url: nil))

        // Help section
        let helpSection = NSStackView()
        helpSection.orientation = .vertical
        helpSection.alignment = .leading
        helpSection.spacing = 4

        let helpTitle = makeLabel("Need Help?", font: .boldSystemFont(ofSize: 13))
        helpSection.addArrangedSubview(helpTitle)

        let helpBody = makeLabel("Community support for open source users:",
                                 font: .systemFont(ofSize: 12),
                                 color: .secondaryLabelColor, wraps: true)
        helpSection.addArrangedSubview(helpBody)
        helpSection.addArrangedSubview(makeLinkButton("OpenZiti Discourse Community",
                                                       url: "https://openziti.discourse.group/"))

        let commercialBody = makeLabel("Commercial support for NetFoundry customers:",
                                       font: .systemFont(ofSize: 12),
                                       color: .secondaryLabelColor, wraps: true)
        helpSection.addArrangedSubview(commercialBody)
        helpSection.addArrangedSubview(makeLinkButton("NetFoundry Support",
                                                       url: "https://support.netfoundry.io"))

        stack.addArrangedSubview(helpSection)

        // Flexible spacer to push close button to bottom
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(spacer)

        // Close button
        let closeBtn = NSButton(title: "Close", target: self, action: #selector(onClose))
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\u{1b}" // Escape key
        stack.addArrangedSubview(closeBtn)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -60),
            helpSection.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 30),
            helpSection.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -30),
        ])
    }

    // MARK: - UI Helpers

    private func makeLogoCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 8

        guard let logoURL = Bundle.main.url(forResource: "netfoundry-logo", withExtension: "svg"),
              let logoImage = NSImage(contentsOf: logoURL) else {
            return card
        }

        let imageView = NSImageView(image: logoImage)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(imageView)

        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 380),
            card.heightAnchor.constraint(equalToConstant: 100),
            imageView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 346),
            imageView.heightAnchor.constraint(equalToConstant: 84),
        ])

        return card
    }

    private func makeSection(title: String, body: String, linkTitle: String?, url: String?) -> NSStackView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 4

        let titleLabel = makeLabel(title, font: .boldSystemFont(ofSize: 13))
        section.addArrangedSubview(titleLabel)

        let bodyLabel = makeLabel(body, font: .systemFont(ofSize: 12),
                                  color: .secondaryLabelColor, wraps: true)
        section.addArrangedSubview(bodyLabel)

        if let linkTitle = linkTitle, let url = url {
            section.addArrangedSubview(makeLinkButton(linkTitle, url: url))
        }

        section.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            section.widthAnchor.constraint(equalToConstant: 440),
        ])

        return section
    }

    private func makeLabel(_ text: String, font: NSFont, color: NSColor = .labelColor, wraps: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        if wraps {
            label.lineBreakMode = .byWordWrapping
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.preferredMaxLayoutWidth = 440
        }
        return label
    }

    private func makeLinkButton(_ title: String, url: String) -> NSButton {
        let btn = NSButton(title: title, target: self, action: #selector(onLinkClick(_:)))
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 12),
        ]
        btn.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        btn.toolTip = url
        return btn
    }

    // MARK: - Actions

    @objc private func onClose() {
        dismiss(self)
    }

    @objc private func onLinkClick(_ sender: NSButton) {
        guard let urlString = sender.toolTip, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
