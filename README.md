# anytls-script

一个面向 VPS 的 AnyTLS 安装脚本，基于 sing-box 生成 AnyTLS 服务端配置，并提供 BBR/TCP 调优、swap 建议、一键规则配置和客户端导入文件导出。

## 功能

- 适配常见 Linux 发行版：Debian/Ubuntu、RHEL/Fedora/CentOS 系、openSUSE、Arch/Manjaro、Alpine。
- 交互式安装引导，也支持 `--yes` 非交互安装。
- 写入 BBR 和常用 TCP 调优配置。
- 检测内存和 swap；未启用 swap 时给出建议，并生成一键应用脚本。
- 默认安全规则：阻断 CN 方向出站规则集和 BitTorrent。
- 支持自定义 geosite/rule_set 规则。
- 导出 AnyTLS 分享链接、v2RayN 分享文本、Clash Verge YAML 和 sing-box 客户端 JSON。

## 安装前准备

VPS 需要：

- 一台 Linux VPS，建议使用 root 用户执行。
- 一个已解析到 VPS 的域名，或者直接使用 VPS 公网 IP。
- 防火墙和云厂商安全组放行安装端口，默认是 TCP `8443`。
- 已安装 `sing-box`。本脚本不会盲目下载二进制文件；正式安装前会检查系统里是否已有 `sing-box`。

### 安装 sing-box

Debian/Ubuntu：

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
sudo chmod a+r /etc/apt/keyrings/sagernet.asc
cat <<'EOF' | sudo tee /etc/apt/sources.list.d/sagernet.sources
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
sudo apt-get update
sudo apt-get install -y sing-box
```

Fedora/RHEL 系：

```bash
sudo dnf config-manager addrepo --from-repofile=https://sing-box.app/sing-box.repo
sudo dnf install -y sing-box
```

其他 Linux 可以使用 sing-box 官方安装脚本，执行前请自行确认来源：

```bash
curl -fsSL https://sing-box.app/install.sh | sudo sh
```

Alpine 可优先尝试：

```bash
sudo apk add sing-box
```

确认安装：

```bash
sing-box version
```

## 在 VPS 上安装 AnyTLS

拉取仓库：

```bash
git clone https://github.com/Redstonexs/anytls-script.git
cd anytls-script
```

先查看将要写入的内容，不做任何系统修改：

```bash
sudo bash anytls-install.sh --dry-run --domain your-domain.example --port 8443 --no-color
```

正式安装：

```bash
sudo bash anytls-install.sh --domain your-domain.example --port 8443
```

如果你想完全非交互安装，并在系统没有 swap 时自动应用推荐 swap：

```bash
sudo bash anytls-install.sh \
  --yes \
  --domain your-domain.example \
  --port 8443 \
  --apply-swap
```

如果你只想生成 swap 建议和一键脚本，不立即启用 swap：

```bash
sudo bash anytls-install.sh \
  --domain your-domain.example \
  --port 8443 \
  --no-swap
```

安装后主要文件：

- 服务端配置：`/etc/sing-box/config.json`
- systemd 服务：`/etc/systemd/system/sing-box-anytls.service`
- Alpine OpenRC 服务：`/etc/init.d/sing-box-anytls`
- BBR/TCP 调优：`/etc/sysctl.d/99-anytls-tuning.conf`
- TLS 证书和私钥：`/etc/anytls/server.crt`、`/etc/anytls/server.key`
- swap 建议：`/etc/anytls/swap-plan.env`
- swap 一键脚本：`/etc/anytls/swap-apply-plan.sh`
- 导出目录：`/etc/anytls/exports`

## 规则配置

默认规则等同于：

```bash
sudo bash anytls-install.sh --domain your-domain.example --rules safe
```

`safe` 会阻断：

- `geoip-cn`
- `geosite-geolocation-cn`
- `geosite-bittorrent`
- `protocol=bittorrent`

只阻断 CN：

```bash
sudo bash anytls-install.sh --domain your-domain.example --rules block-cn
```

只阻断 BitTorrent：

```bash
sudo bash anytls-install.sh --domain your-domain.example --rules block-bt
```

不启用内置阻断规则：

```bash
sudo bash anytls-install.sh --domain your-domain.example --rules none
```

添加常见 geosite 规则，例如阻断 OpenAI：

```bash
sudo bash anytls-install.sh \
  --domain your-domain.example \
  --custom-rule-set openai
```

添加完整自定义 rule_set：

```bash
sudo bash anytls-install.sh \
  --domain your-domain.example \
  --custom-rule-set tag=geosite-netflix,url=https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-netflix.srs,outbound=block,format=binary
```

`outbound` 可选：

- `block` 或 `reject`：拒绝匹配流量。
- `direct`：匹配流量直连。

## 客户端导入

安装完成后查看导出文件：

```bash
sudo ls -l /etc/anytls/exports
```

常用文件：

- `share-link.txt`：通用 `anytls://` 分享链接。
- `v2rayn-share.txt`：给 v2RayN 导入的分享链接。
- `clash-verge.yaml`：给 Clash Verge Rev 使用的 YAML。
- `sing-box-client.json`：sing-box 客户端 outbound 示例。
- `subscription.txt`：包含分享链接和客户端 JSON 路径。

查看分享链接：

```bash
sudo cat /etc/anytls/exports/share-link.txt
```

把 `anytls://...` 链接复制到 Clash Verge Rev 或 v2RayN 中导入即可。

## 管理服务

systemd 系统：

```bash
sudo systemctl status sing-box-anytls
sudo systemctl restart sing-box-anytls
sudo journalctl -u sing-box-anytls --output cat -f
```

Alpine/OpenRC：

```bash
sudo rc-service sing-box-anytls status
sudo rc-service sing-box-anytls restart
```

## 常用参数

```text
--dry-run          只显示安装计划，不写入文件
--yes             使用默认值/传入值进行非交互安装
--domain HOST     客户端连接使用的域名或公网 IP
--port PORT       AnyTLS 监听端口，默认 8443
--password VALUE  指定 AnyTLS 密码；不填则自动生成
--alpn LIST       可选 ALPN，例如 h2,http/1.1
--rules LIST      block-cn、block-bt、safe、none
--custom-rule-set 自定义 geosite/rule_set
--apply-swap      无 swap 时按建议创建并启用 swap
--no-swap         只写 swap 建议，不立即启用
--export-dir PATH 自定义导出目录
```

查看完整帮助：

```bash
bash anytls-install.sh --help
```

## 注意事项

- 请先用 `--dry-run` 检查计划，确认域名、端口和规则符合预期。
- 生产环境建议使用自己的真实证书；脚本默认会在缺少证书时生成自签证书。
- 导出的分享链接包含连接密码，请不要公开发布。
- 如果 VPS 已有 swap，脚本不会创建新的 swap。
- 如果系统没有 `sing-box`，正式安装会停止并提示先安装。

## 参考

- sing-box Linux 安装文档：https://github.com/sagernet/sing-box/blob/v1.13.14/docs/installation/package-manager.md
- sing-box AnyTLS inbound：https://github.com/sagernet/sing-box/blob/v1.13.14/docs/configuration/inbound/anytls.md
- sing-box AnyTLS outbound：https://github.com/sagernet/sing-box/blob/v1.13.14/docs/configuration/outbound/anytls.md
