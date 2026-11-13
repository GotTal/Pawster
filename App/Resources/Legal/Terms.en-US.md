# Pawster Terms of Use

Version: 2026-11-13.3. Updated: November 13, 2026.

Developer: GotTal. Contact: xkstudio@icloud.com. Project: https://github.com/GotTal/Pawster.

## 1. Review and choice

Read these Terms and the Privacy Policy before enabling operations, especially the engine and serious risks in section 4 and the responsibility provisions in section 7. On first use or after a policy update, actively check the risk acknowledgement and then select Agree and Enable. The acknowledgement is not preselected. Checking it alone, closing a page, browsing content or updating the app does not complete consent. Until you explicitly agree, importing, pairing, path queries, injection, registration refresh, rollback and NeoSpring remain disabled. If you select Not Now, you can still view previously imported local content, operation history and legal documents, and delete local wallpaper packs, clear diagnostic logs and remove pairing credentials.

## 2. Purpose of the tool

Pawster is an open-source iOS Collections wallpaper tool. It provides local pack management, device pairing, PosterBoard path queries, wallpaper file injection, registration refresh, and rollback within the scope of its own operations. It is not an official Apple product. System updates, device configuration, and signing methods affect compatibility. An operation reported as complete does not establish that the system has adopted the wallpaper; check on your device.

## 3. Authorization for devices and content

Operate only devices you are authorized to manage. Ensure that wallpaper content and files have a lawful source and the necessary permissions. Do not use this tool to infringe privacy, intellectual property, or another person’s device security. Imported content remains the property of its respective rights holders. These Terms neither transfer ownership nor authorize the developer to upload or publish it.

## 4. Injection engines and serious risks

Depending on the system version, Pawster uses bad_query or worse_query to access restricted directories. These experimental mechanisms rely on system implementation details, defects or non-public behavior, and write files to the PosterBoard system wallpaper container. They are not an Apple-supported public wallpaper installation API. A listed system version, a successful read-only check or a previous successful operation does not guarantee the safety of a later operation.

**Injection engines and related system operations may corrupt system or wallpaper data, lose important data, break wallpapers or other functions, crash the system interface, cause repeated restarts, prevent normal startup or cause other unforeseen problems. Severe problems may require restoring or reinstalling the system, which may erase device data; some data may be unrecoverable.**

**Back up important data before operating and decide whether you can accept device unavailability, a system restore or unrecoverable data loss. Select Not Now if you cannot accept these risks. Backups, write verification, receipts and rollback can help reduce or investigate risks; they cannot eliminate them or guarantee complete recovery.**

**Injection changes files associated with system wallpapers. Back up important data and review the paths and target count in the injection plan first. Avoid power loss, force-quitting, and duplicate operations while writing.** The tool attempts to preserve existing wallpapers and record newly added content, but cannot promise fault-free operation on every system version. Rollback depends on existing files and verification results; later file changes may prevent safe rollback.

**NeoSpring attempts to refresh the system interface. The screen may briefly go black, return to the Lock Screen, or interrupt the app or related processes; the refresh may also have no effect.** Save other work first. Manual refresh requests confirmation each time. Automatic refresh is off by default and requires acknowledging the notice when first enabled; it then runs after wallpaper writes pass verification without asking each time. You can turn it off at any time. It does not reboot the device or replace registration refresh or backups, and success is not guaranteed.

AirTraffic/Airlift is an additional experimental folder-transfer method requiring valid pairing, a local VPN and Apple Books sync services. It temporarily changes Books sync state and saves a local recovery backup; cancellation, disconnection or app termination can leave recovery pending. It cannot read back the target directory. “Sent” does not establish successful installation, wallpaper visibility or automatic rollback. This method does not overwrite PosterBoard preferences or trigger automatic refresh; you may inspect the result and choose a manual refresh.

Pocket Poster/Trash is another experimental transfer method, using a temporary .Trash link in this app and the system file-move service. It provides no general file-read access. Upstream compatibility claims do not constitute Pawster device acceptance; a manually entered UUID does not prove destination identity. Incorrect targets, concurrent file operations, cancellation, app termination or system patches can cause failure, leftover copies or other effects. Keep the app in the foreground and avoid managing its files concurrently; cancellation may wait for a running system file operation to return. Completion does not prove wallpaper visibility or verified target content. No automatic refresh, preference replacement or wallpaper rollback is provided. The .Trash link handles this app’s temporary copies only; no collection-clearing, system-language switch or automatic reset is exposed.

## 5. Pairing security and privacy

Pairing files may contain certificates, device identifiers, and keys. Exposure may affect device security. Do not publish pairing files or codes. Connect only to trusted destinations that you are authorized to manage. Before a system connection, you are separately informed about pairing credential processing and given a choice. See the Privacy Policy for data categories, purposes, retention, and deletion. You do not need to give the developer your Apple ID password.

## 6. Free official distribution and open-source licenses

**GotTal distributes Pawster free of charge through the project's GitHub Releases. Using the app does not require purchasing an activation code, membership or feature unlock from GotTal.** Official downloads: https://github.com/GotTal/Pawster/releases/latest.

If you paid another channel to obtain the app, ask the seller what was charged for, where the file came from and what support was promised. Your payment does not mean that GotTal received it, participated in the transaction or promised extra services. You can still obtain an official version free of charge and verify its release signature. If you believe a transaction was misrepresented, retain the transaction record and contact the seller or platform, or exercise applicable legal rights. This notice does not guarantee a third-party refund.

Free official distribution describes GotTal's offering; it does not restrict paid redistribution or independent services permitted by the applicable open-source license. Third parties should accurately state their identity, charges and obligations. Wallpaper content, third-party installation and signing services may have their own terms and charges and are not included in this promise of a free app.

Project code is licensed under GPL-3.0-or-later. Third-party code is subject to its respective applicable licenses. See Open-source Notices for sources, copyrights, and authorization questions still requiring verification. These Terms do not reduce rights to copy, study, modify, reverse-engineer, or redistribute granted by an open-source license, and do not supply missing permission for third-party content. Follow the applicable licenses when using, modifying, or distributing code.

## 7. Responsibility and support

This tool is provided in its current development state. The developer does not promise support for every device or system version, continued availability of a particular function, or success of injection, registration, system refresh, rollback or data recovery. Decide whether to enable it based on your backups, the importance of the device and your tolerance for risk. For problems arising from system differences, experimental engine behavior, third-party modifications, interruptions or improper operation, open-source warranty and liability limitations apply only to the extent permitted by applicable law; compensation and recovery results are not promised.

Stop repeating the affected system operation if a problem occurs and report it on the project page. Contact the developer privately by email for personal information or pairing data; do not post secrets in public issues.

These Terms do not exclude responsibility that the developer must bear under applicable law, including liability that cannot lawfully be excluded for personal injury or property loss caused intentionally or through gross negligence. They do not remove other statutory user rights. Warranty and liability provisions in open-source licenses apply to the extent permitted by applicable law.

## 8. Minors

Minors should read and use the tool with guidance from a guardian. If processing personal information of a user under fourteen is involved, a guardian must provide legally required consent and assist with devices, content, and credentials. The app does not actively collect age or guardian identity documents. Do not submit another person’s personal information or secret files as test material.

## 9. Changes, exit, and disputes

Withdraw consent under Settings → Privacy & Data to disable related operations. Exiting or uninstalling the app does not automatically roll back wallpapers already installed in the system; inspect the operation history first if rollback is needed. Material changes to these Terms or data processing will be explained in a new version, and legally necessary consent will be requested again. Silence or continued browsing does not replace consent.

These Terms comply with mandatory provisions of the laws of the People’s Republic of China where applicable. You may first contact the developer to seek a resolution. If that fails, seek relief from a court with lawful jurisdiction. These Terms do not restrict statutory complaint, reporting, or litigation channels. Invalidity of one provision does not invalidate other lawful, effective provisions.
