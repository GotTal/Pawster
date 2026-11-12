# Pawster Privacy Policy and Data Processing Notice

Version: 2026-11-12.2. Updated: November 12, 2026.

Developer and project contact: GotTal. Privacy contact: xkstudio@icloud.com. Project: https://github.com/GotTal/Pawster. This policy covers Pawster released by this project. Data behavior of third-party modified versions must be checked separately.

## 1. Principles and choices

The app provides local wallpaper management and device connections that you initiate. It has no developer-operated accounts, analytics, advertising, or automatic upload service. On first use, it presents the Terms and this Policy for an explicit choice. If operations remain disabled, you can still browse local caches, history, and legal documents, and perform local deletion and cleanup. Import, query, and write operations run only after you enable them. Pairing credential processing is separately explained and requires separate consent.

## 2. Wallpaper files

The app reads the .tendies file you select. Its private directory stores a copy of the archive, extracted content, name, size, verification digest, descriptor paths, and available preview images to support selection, plan review, and write verification. Files may contain personal content belonging to you or others; ensure that you are authorized to use them. The app accesses selected import files and its own data, and does not request access to your entire photo library.

Local packs remain until you swipe left to delete them from the wallpaper list or uninstall the app. Deletion removes this tool’s imported copy. It does not delete the original file selected from Files, installed system wallpapers, or operation history.

## 3. Pairing and system connections

When importing a pairing file or pairing on the device, the app processes protocol-required device and host identifiers, certificates, keys, and connection parameters. Exact fields vary by pairing protocol. They authenticate your configured device, establish connections, and query the PosterBoard container. **These credentials are security-sensitive: exposure may affect device security. A separate notice explains the purpose and risk before the operation. Canceling does not start the related connection.**

Credentials are stored as pairing.plist in the app’s private directory. Pairing may also create temporary pending files; host parameters used by pairing are stored in local preferences. Credentials are retained for later connections until replaced, removed in Settings, or deleted with the app. Removal also clears matching temporary pairing files and host pairing parameters maintained by this tool. It does not delete externally saved files or revoke trust already established in the system or other tools.

On-device pairing publishes a Bonjour service for system discovery. The pairing code is used only in the current session, for approximately 180 seconds at most, and is cleared from the app when the session ends. It is copied to the local clipboard only when you choose Copy, with an expiration time. When pairing ends, the app clears the clipboard only if it still contains the code copied by that session. The app does not intentionally include pairing codes in diagnostic logs.

Automatic mode chooses a Peer IP from local tunnel interfaces and may also try fallback addresses 10.7.0.1, 10.7.0.2, and 10.7.0.3. An applied manual override uses only the specified peer, without those fallback addresses. Typically, LocalDevVPN connects to system services on the same device. If you configure a remote private address, protocol data may reach that destination and its network. Check that the destination and network are trustworthy. The tool does not automatically upload credentials to the developer; this does not mean that every user-configured connection stays on the device.

After you consent to enable operations, the foreground app reads local IPv4 interface names, addresses, netmasks, and point-to-point destinations, and queries the local route source for the chosen Peer IP to display the VPN badge and Iface IP. This check sends no probe packets and reads no pairing file. It does not establish the VPN provider's identity or pairing-service availability. Results remain in process memory, update about every two seconds in the foreground, stop updating in the background, and are not automatically uploaded.

## 4. Paths, writes, and operation records

The app processes the system version, target container UUID and path, wallpaper extension and directory information, necessary container identity information, and verification results to select a compatible engine and avoid writing to the wrong destination. A write records a transaction identifier, time, target paths, digests, status, and errors. Registration refresh may save a copy of the previous preferences for verification and rollback.

Records and backups remain in the app’s private directory for review and rollback until the app is uninstalled. They are not automatically deleted when a pack is deleted, diagnostic logs are cleared, or consent is withdrawn, because doing so would lose rollback evidence. For complete deletion, first roll back system content if needed, then uninstall the app. Uninstalling alone does not remove wallpapers already installed in the system container.

## 5. Preferences and consent records

The app reads the preferred system language on the device to select bundled interface text and offline documents. It does not send the device language to the developer for matching or download language packs. Chinese first uses an available regional or script translation and otherwise Simplified Chinese. Other unsupported languages use US English.

The device stores your appearance, animated background choice, log limit, Automatic NeoSpring choice, the acknowledged automatic refresh risk notice version, the peer override, and saved gateway and container paths. The Getting Started guide stores its current step, completion or deferral flags, and your confirmation that Developer Mode is enabled locally to resume progress; guide progress does not store pairing codes. The app records the accepted policy version and time, and the pairing processing consent version, to remember your choices and request renewed consent after a policy version change. Withdrawal clears the corresponding consent records. Other preferences can be changed. Uninstalling removes the app’s own data; system backup and restoration behavior is controlled by iOS.

## 6. Diagnostics and sharing

In-app diagnostic logs help investigate problems. They are held in the current process’s memory and are off by default. You can explicitly choose a limit of 100, 300, or 1,000 entries in Settings. The oldest entries are removed when the limit is exceeded. Logs are not restored from disk after the process ends. Turning logging off clears current in-memory logs. iOS and dependencies may produce separate runtime logs that are not controlled by this limit.

Logs and operation errors may contain filenames, paths, container UUIDs, gateway IP addresses, digests, and error details. Review them before sharing. The app does not intentionally include pairing file contents, certificates, private keys, or pairing codes in exports. Imported filenames and third-party error messages may nevertheless contain personal information.

Preparing diagnostic logs creates a temporary text file and adds operation identifiers, statuses, target counts, and engine summaries. The file remains until diagnostic logs are cleared, the system cleans temporary files, or the app is uninstalled. Clear Diagnostic Logs removes this export and current in-memory logs, not transaction records. When you share, you choose the recipient; the app cannot retract copies you have shared or saved elsewhere.

## 7. Permissions and background behavior

The system file picker grants access to selected import files. Pairing and connections may require local network permission, Developer Mode, and a VPN that you configure. During pairing, silent audio keeps the session alive and Picture in Picture shows steps and the code. This does not record sound or use the microphone. Current functions do not request Contacts, Location, Camera, or Microphone access. Denying a required permission affects functions that depend on it, not policy access or local data management.

## 8. Protection and external services

The app stores data in iOS private directories, requests file protection when saving credentials, and marks app data directories as excluded from backup. These measures do not guarantee absolute security under every system, signing environment, or backup method. Protect access to your device, do not share pairing credentials, and avoid untrusted networks.

See About → Open-source Notices for dependencies and sources. SideStore, LocalDevVPN, iOS, file providers, GitHub, email services, and sharing recipients operate independently and may process data under their own rules. Opening GitHub or sending email lets those external services process access, account, or message information and may involve services outside your country. These are not automatic uploads by this app.

If you email feedback, the developer receives your email address, message, and attachments solely to handle the inquiry or rights request. Avoid unnecessary secrets or third-party personal information. Information is retained only until handling and reasonably necessary follow-up verification have ended, unless law requires longer retention. Contact the developer to request deletion. Feedback attachments are not publicly disclosed; legally required processing follows applicable law.

## 9. Access, correction, deletion, and withdrawal

View local packs and history or change connection parameters in the app. Swipe left to delete a pack. Settings provides log cleanup, credential removal, and consent withdrawal. You can separately withdraw pairing processing consent to stop subsequent related connections. This does not delete stored credentials; use Remove Pairing Credentials for deletion. Withdrawing overall consent stops new operations that need consent, clears current in-app diagnostics and their temporary export, and turns off Automatic NeoSpring. Retained local data remains available for browsing, deletion, and your further decisions. Withdrawal does not affect prior lawful processing. To roll back a system wallpaper, enable the necessary connection again and inspect the record before proceeding.

Contact xkstudio@icloud.com to request an explanation, access, correction, a copy, or deletion of information about you actually held by the developer, or to raise a complaint. We will verify and handle requests according to law and explain when a request cannot be fulfilled. Only information necessary to verify identity and the request will be sought. Local data is held on your device; the developer cannot remotely read or delete it for you. Use the local controls above. There are no registered accounts, so there is no separate account closure process.

## 10. Minors and updates

The app does not actively collect age or children’s information. A guardian must provide legally required consent and guidance if processing personal information of a child under fourteen is involved. Guardians may email the developer if a child’s information has been improperly supplied.

You can read this policy offline at any time under Settings → About. Material changes to processing purposes, methods, or data categories will update the version and request legally required consent again. Failure to object or continued browsing does not replace consent. This is a data processing notice, not a regulatory certification, security audit certificate, or guarantee of absolute safety.
