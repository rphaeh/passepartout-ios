//
//  WizardHostViewController.swift
//  Passepartout-iOS
//
//  Created by Davide De Rosa on 9/4/18.
//  Copyright (c) 2018 Davide De Rosa. All rights reserved.
//
//  https://github.com/keeshux
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import TunnelKit
import SwiftyBeaver

private let log = SwiftyBeaver.self

class WizardHostViewController: UITableViewController, TableModelHost, Wizard {
    private struct ParsedFile {
        let filename: String
        
        let hostname: String
        
        let configuration: TunnelKitProvider.Configuration
    }

    @IBOutlet private weak var itemNext: UIBarButtonItem!
    
    private let existingHosts: [HostConnectionProfile] = {
        var hosts: [HostConnectionProfile] = []
        let service = TransientStore.shared.service
        let ids = service.profileIds()
        for id in ids {
            guard let host = service.profile(withId: id) as? HostConnectionProfile else {
                continue
            }
            hosts.append(host)
        }
        return hosts.sorted { $0.title < $1.title }
    }()
    
    private var parsedFile: ParsedFile? {
        didSet {
            useSuggestedTitle()
        }
    }

    private var createdProfile: HostConnectionProfile?

    weak var delegate: WizardDelegate?
    
    // MARK: TableModelHost

    lazy var model: TableModel<SectionType, RowType> = {
        let model: TableModel<SectionType, RowType> = TableModel()
        model.add(.meta)
        if !existingHosts.isEmpty {
            model.add(.existing)
            model.setHeader(L10n.Wizards.Host.Sections.Existing.header, for: .existing)
        }
        model.set([.titleInput], in: .meta)
        model.set(.existingHost, count: existingHosts.count, in: .existing)
        return model
    }()
    
    func reloadModel() {
    }
    
    // MARK: UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = L10n.Organizer.Sections.Hosts.header
        itemNext.title = L10n.Global.next
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        useSuggestedTitle()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        cellTitle?.field.becomeFirstResponder()
    }
    
    // MARK: Actions
    
    func setConfigurationURL(_ url: URL) throws {
        log.debug("Parsing configuration URL: \(url)")
        
        let filename = url.deletingPathExtension().lastPathComponent
        let hostname: String
        let configuration: TunnelKitProvider.Configuration
        do {
            (hostname, configuration) = try TunnelKitProvider.Configuration.parsed(from: url)
        } catch let e {
            log.error("Could not parse .ovpn configuration file: \(e)")
            throw e
        }
        parsedFile = ParsedFile(filename: filename, hostname: hostname, configuration: configuration)
    }
    
    private func useSuggestedTitle() {
        guard let field = cellTitle?.field else {
            return
        }
        if field.text?.isEmpty ?? true {
            field.text = parsedFile?.filename
        }
    }
    
    @IBAction private func next() {
        guard let enteredTitle = cellTitle?.field.text?.trimmingCharacters(in: .whitespaces), !enteredTitle.isEmpty else {
            return
        }
        guard let file = parsedFile else {
            return
        }

        let profile = HostConnectionProfile(title: enteredTitle, hostname: file.hostname)
        profile.parameters = file.configuration

        guard !TransientStore.shared.service.containsProfile(profile) else {
            let alert = Macros.alert(title, L10n.Wizards.Host.Alerts.existing)
            alert.addDefaultAction(L10n.Global.ok) {
                self.next(withProfile: profile)
            }
            alert.addCancelAction(L10n.Global.cancel)
            present(alert, animated: true, completion: nil)
            return
        }
        next(withProfile: profile)
    }
    
    private func next(withProfile profile: HostConnectionProfile) {
        createdProfile = profile

        let accountVC = StoryboardScene.Main.accountIdentifier.instantiate()
        accountVC.delegate = self
        navigationController?.pushViewController(accountVC, animated: true)
    }
    
    private func finish(withCredentials credentials: Credentials) {
        guard let profile = createdProfile else {
            fatalError("No profile created?")
        }
        dismiss(animated: true) {
            self.delegate?.wizard(didCreate: profile, withCredentials: credentials)
        }
    }

    @IBAction private func close() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: -

extension WizardHostViewController {
    enum SectionType: Int {
        case meta
        
        case existing
    }
    
    enum RowType: Int {
        case titleInput
        
        case existingHost
    }
    
    private var cellTitle: FieldTableViewCell? {
        guard let ip = model.indexPath(row: .titleInput, section: .meta) else {
            return nil
        }
        return tableView.cellForRow(at: ip) as? FieldTableViewCell
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return model.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return model.header(for: section)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.count(for: section)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch model.row(at: indexPath) {
        case .titleInput:
            let cell = Cells.field.dequeue(from: tableView, for: indexPath)
            cell.caption = L10n.Wizards.Host.Cells.TitleInput.caption
            cell.captionWidth = 100.0
            cell.field.placeholder = L10n.Wizards.Host.Cells.TitleInput.placeholder
            cell.field.clearButtonMode = .always
            cell.field.returnKeyType = .done
            cell.delegate = self
            return cell
            
        case .existingHost:
            let profile = existingHosts[indexPath.row]
            
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = profile.title
            cell.accessoryType = .none
            cell.isTappable = true
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch model.row(at: indexPath) {
        case .existingHost:
            guard let titleIndexPath = model.indexPath(row: .titleInput, section: .meta) else {
                fatalError("Could not found title cell?")
            }
            let profile = existingHosts[indexPath.row]
            let cellTitle = tableView.cellForRow(at: titleIndexPath) as? FieldTableViewCell
            cellTitle?.field.text = profile.title
            tableView.deselectRow(at: indexPath, animated: true)
            
        default:
            break
        }
    }
}

// MARK: -

extension WizardHostViewController: FieldTableViewCellDelegate {
    func fieldCellDidEdit(_: FieldTableViewCell) {
    }

    func fieldCellDidEnter(_: FieldTableViewCell) {
        next()
    }
}

extension WizardHostViewController: AccountViewControllerDelegate {
    func accountController(_: AccountViewController, didEnterCredentials credentials: Credentials) {
    }
    
    func accountControllerDidComplete(_ vc: AccountViewController) {
        finish(withCredentials: vc.credentials)
    }
}