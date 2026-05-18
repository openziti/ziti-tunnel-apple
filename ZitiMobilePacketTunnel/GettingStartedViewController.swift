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

import UIKit

class GettingStartedViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Get Started"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(onDone))
        setupUI()
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -48),
        ])

        // Welcome heading and branding
        let heading = makeLabel("Welcome to Ziti Mobile Edge", font: .boldSystemFont(ofSize: 20), alignment: .center)
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(makeBrandingView())
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // Separator
        let sep = UIView()
        sep.backgroundColor = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        stack.addArrangedSubview(sep)

        // Deploy a Network
        stack.addArrangedSubview(makeSection(
            title: "Deploy a Network",
            body: "New to OpenZiti? Get started by deploying your own zero trust network overlay.",
            linkTitle: "Learn how to deploy a network",
            url: "https://netfoundry.io/docs/openziti/#deploy_an_overlay"))

        // Already have a network?
        stack.addArrangedSubview(makeSection(
            title: "Already have a network?",
            body: "Tap the \"+\" button in the Identities section to add an identity. Your network admin can provide an enrollment JWT file, QR code, or enrollment URL.",
            linkTitle: nil,
            url: nil))

        // Need Help?
        let helpSection = UIStackView()
        helpSection.axis = .vertical
        helpSection.spacing = 4

        helpSection.addArrangedSubview(makeLabel("Need Help?", font: .boldSystemFont(ofSize: 15)))
        helpSection.addArrangedSubview(makeLabel("Community support for open source users:",
                                                  font: .systemFont(ofSize: 14), color: .secondaryLabel))
        helpSection.addArrangedSubview(makeLinkButton("OpenZiti Discourse Community",
                                                       url: "https://openziti.discourse.group/"))
        helpSection.setCustomSpacing(12, after: helpSection.arrangedSubviews.last!)
        helpSection.addArrangedSubview(makeLabel("Commercial support for NetFoundry customers:",
                                                  font: .systemFont(ofSize: 14), color: .secondaryLabel))
        helpSection.addArrangedSubview(makeLinkButton("NetFoundry Support",
                                                       url: "https://support.netfoundry.io"))
        stack.addArrangedSubview(helpSection)
    }

    // MARK: - UI Helpers

    private func makeBrandingView() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2

        let byLabel = UILabel()
        byLabel.text = "by NetFoundry"
        byLabel.font = .systemFont(ofSize: 18)
        byLabel.textColor = .label
        byLabel.textAlignment = .center
        stack.addArrangedSubview(byLabel)

        let taglineLabel = UILabel()
        taglineLabel.text = "Developers of OpenZiti"
        taglineLabel.font = .italicSystemFont(ofSize: 13)
        taglineLabel.textColor = .tertiaryLabel
        taglineLabel.textAlignment = .center
        stack.addArrangedSubview(taglineLabel)

        return stack
    }

    private func makeSection(title: String, body: String, linkTitle: String?, url: String?) -> UIStackView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 4

        section.addArrangedSubview(makeLabel(title, font: .boldSystemFont(ofSize: 15)))
        section.addArrangedSubview(makeLabel(body, font: .systemFont(ofSize: 14), color: .secondaryLabel))

        if let linkTitle = linkTitle, let url = url {
            section.addArrangedSubview(makeLinkButton(linkTitle, url: url))
        }

        return section
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor = .label, alignment: NSTextAlignment = .natural) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = 0
        return label
    }

    private func makeLinkButton(_ title: String, url: String) -> UIButton {
        let btn = UIButton(type: .system)
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: UIFont.systemFont(ofSize: 14),
        ]
        btn.setAttributedTitle(NSAttributedString(string: title, attributes: attrs), for: .normal)
        btn.contentHorizontalAlignment = .leading
        btn.accessibilityHint = url
        btn.addTarget(self, action: #selector(onLinkTap(_:)), for: .touchUpInside)
        return btn
    }

    // MARK: - Actions

    @objc private func onDone() {
        dismiss(animated: true)
    }

    @objc private func onLinkTap(_ sender: UIButton) {
        guard let urlString = sender.accessibilityHint, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
