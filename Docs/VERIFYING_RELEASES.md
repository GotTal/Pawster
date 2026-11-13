# Verify a Pawster Release

[简体中文](#验签说明)

Release files are signed with a dedicated **Ed25519** private key. This verifies file integrity and continuity with the pinned release key. It is separate from Apple's app signing and SideStore re-signing.

The downloadable X.509 certificate is **self-issued**. It contains the verification public key; it does not certify a legal identity through a public certificate authority. Do not install it as a trusted root certificate on your device.

## Trusted certificate

Certificate DER SHA-256 fingerprint (first published with v0.2.0):

```text
7561047aba5fd9e4039396ce96bd90e02a1deaa6587cd9d9671f1f58896038ac
```

Compare this value with a separately trusted copy of this page or a previously saved fingerprint. A certificate downloaded beside a file is not, by itself, proof of its origin: an attacker able to replace every file could also supply a different certificate. Keep the fingerprint for future releases. Any future key rotation must be explicitly documented.

## Verify with OpenSSL 3

Replace `VERSION` in the filenames below with the version shown on the Release you downloaded. Obtain every asset from that same release. The pinned signing certificate is independent of the app version.

Download `Pawster-VERSION.ipa`, `Pawster-VERSION.ipa.sig`, `SHA256SUMS`, `SHA256SUMS.sig`, and `Pawster-release-signing-cert.pem` from the [latest Release](https://github.com/GotTal/Pawster/releases/latest). Download the other attached assets too if checking the entire manifest.

1. Display the certificate fingerprint and compare it with the value above:

```sh
openssl x509 -in Pawster-release-signing-cert.pem -noout -fingerprint -sha256
```

2. Authenticate the checksum manifest and the original IPA:

```sh
openssl pkeyutl -verify -certin -inkey Pawster-release-signing-cert.pem -rawin -in SHA256SUMS -sigfile SHA256SUMS.sig
openssl pkeyutl -verify -certin -inkey Pawster-release-signing-cert.pem -rawin -in Pawster-VERSION.ipa -sigfile Pawster-VERSION.ipa.sig
```

Both commands must succeed. These are raw binary detached signatures, not text signatures or `.p7s` files. Ed25519 uses `-rawin` without a digest option.

3. After authenticating the manifest, check its hashes from the download directory:

```sh
# Linux
sha256sum -c SHA256SUMS
# macOS
shasum -a 256 -c SHA256SUMS
```

On Windows, compare the IPA's result with its entry in the authenticated manifest:

```powershell
Get-FileHash .\Pawster-VERSION.ipa -Algorithm SHA256
```

To verify every asset on Windows, macOS or Linux, use the attached `release-integrity.py` and `requirements-release.txt` after obtaining the verifier from a trusted repository checkout:

```sh
python -m pip install -r requirements-release.txt
python release-integrity.py verify --folder . --certificate Pawster-release-signing-cert.pem --fingerprint 7561047aba5fd9e4039396ce96bd90e02a1deaa6587cd9d9671f1f58896038ac
```

The attached `Pawster-VERSION-source.tar.gz` is included in the signed checksum manifest. GitHub's automatically generated “Source code” archives are separate downloads and are not covered by this manifest. `release.json` records the source commit, build run and package hash. File signatures do not prove reproducibility, absence of defects, or real-device compatibility.

Verify **before** importing into SideStore. Re-signing changes the IPA, so the original download's signature will no longer match the resulting re-signed package.

## Maintainer key custody

Private-key operations in `Scripts/release-integrity.py` require Windows and the original signing user's DPAPI context. Only the encrypted private-key blob is stored locally, outside the repository. No private key is supplied to Actions or Release assets. A DPAPI blob alone is not a portable backup: protect the Windows account and its recovery material. Loss of the signing identity requires an announced key rotation; never silently replace the published certificate.

## 验签说明

请将命令文件名中的 `VERSION` 换为所下载 Release 的版本号，并从同一发行页取得所有附件。证书指纹独立于 App 版本，不随普通版本更新而更换。

Release 使用独立 **Ed25519 公私钥**为原始 IPA 和 `SHA256SUMS` 清单生成分离签名，用来检查文件是否被修改，并确认签名来自已固定指纹的发布密钥。这与 Apple 应用签名、SideStore 安装重签不同。

`Pawster-release-signing-cert.pem` 是自签发的公钥证书，不是第三方 CA 对开发者身份的认证，也不需要安装为系统根证书。首次使用请从可信渠道核对上方证书 SHA-256 指纹并保存；只下载与文件放在一起的证书，不能独立证明来源。

下载 Release 附件后，按上面的 OpenSSL 3 命令依次核对证书指纹、验证清单签名和 IPA 签名，再比较 SHA-256。两条验签命令都必须成功。Windows 可用 `Get-FileHash` 核对单个文件，也可使用附带 Python 工具检查整份清单。验签工具本身应从可信的仓库副本取得。

清单包含明确附带的源码归档 `Pawster-VERSION-source.tar.gz`，不包含 GitHub 自动生成的源码下载。`release.json` 记录来源提交、构建记录和安装包摘要。签名不代表软件没有缺陷、构建可复现或所有机型已验证。

请在 SideStore 重签**之前**完成验签；重签会改变文件，重签后的 IPA 不再匹配原始发布签名。私钥仅在发布者本机通过 Windows 当前用户 DPAPI 加密保存，不进入仓库或 GitHub Actions；公钥轮换会另行公告。
