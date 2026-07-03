# anytls-script

一个面向 VPS 的 AnyTLS 自动安装脚本，基于 sing-box 生成 AnyTLS 服务端配置，并提供 acme.sh 自动证书签发和维护、BBR/TCP 调优、swap 建议、一键规则配置和客户端导入文件导出。

## 推荐安装方式

在 VPS 上执行一条命令即可。脚本会自动完成这些前置工作：

- 安装基础依赖：`curl`、`git`、`openssl`、`socat`、`iproute2` 等。
- 安装或复用 `sing-box`。
- 拉取本仓库到 `/opt/anytls-script`。
- 运行 `anytls-install.sh`，默认通过 acme.sh 为域名签发证书并完成 AnyTLS 服务端安装。

默认安装方式要求使用已解析到 VPS 的域名：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example
```

如果只是测试，或确实要使用 IP，可以显式要求自签证书：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain 203.0.113.10 --self-signed
```

如果希望在系统没有 swap 时自动应用推荐 swap：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --apply-swap
```

不传 `--domain` 时，安装器会尝试取本机第一个 IP；默认 ACME 模式会拒绝 IP，因此生产环境请显式传入已解析到 VPS 的域名。只有传入 `--self-signed` 时才会生成自签证书。

## 安装前需要确认

- VPS 是 Linux 系统，建议使用 Debian/Ubuntu、RHEL/Fedora/CentOS 系、openSUSE、Arch/Manjaro 或 Alpine。
- 使用 root 权限执行，推荐命令里已经使用 `sudo bash`。
- 防火墙和云厂商安全组放行 AnyTLS 端口，默认 TCP `443`。
- DNS 已把 `--domain` 指向当前 VPS。
- acme.sh standalone 签发期间需要 TCP `80` 可被公网访问，且没有其他程序占用。

## 自动安装参数

`install.sh` 是 bootstrap 脚本，负责前置工作。它会把大多数参数原样传给 `anytls-install.sh`。

常用命令：

```bash
# 默认安全规则，非交互安装
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example

# 指定端口和密码
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --port 9443 --password 'your-strong-password'

# 指定 v2RayN 导入时使用的 TLS fingerprint 和 ALPN
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --fingerprint chrome --alpn h2,http/1.1

# 测试或 IP 场景才显式使用自签证书
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain 203.0.113.10 --self-signed

# 关闭内置阻断规则
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --rules none

# 添加自定义 geosite 规则
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --custom-rule-set openai
```

bootstrap 专用参数：

```text
--bootstrap-install-dir PATH  仓库安装目录，默认 /opt/anytls-script
--bootstrap-repo URL          仓库地址
--bootstrap-branch NAME       分支，默认 main
--skip-sing-box-install       不自动安装 sing-box
--interactive                 不自动追加 --yes，改用交互确认
```

例如安装到自定义目录：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --bootstrap-install-dir /opt/my-anytls --domain your-domain.example
```

## 功能

- 适配常见 Linux 发行版：Debian/Ubuntu、RHEL/Fedora/CentOS 系、openSUSE、Arch/Manjaro、Alpine。
- 默认通过管道命令全自动安装。
- 交互式安装引导，也支持 `--yes` 非交互安装。
- 默认使用 acme.sh 为域名签发证书，并通过 acme.sh 续签后自动重启服务。
- 仅在显式传入 `--self-signed` 时生成自签证书。
- 写入 BBR 和常用 TCP 调优配置。
- 检测内存和 swap；未启用 swap 时给出建议，并生成一键应用脚本。
- 默认安全规则：阻断 CN 方向出站规则集和 BitTorrent。
- 支持自定义 geosite/rule_set 规则。
- 导出 AnyTLS 分享链接、v2RayN 分享文本、Clash Verge YAML 和 sing-box 客户端 JSON。
- v2RayN 分享链接默认带 `fp=chrome` 和 `alpn=h2,http/1.1`，导入后会自动填写 Fingerprint 和 ALPN。

## 安装后文件

- 仓库目录：`/opt/anytls-script`
- 服务端配置：`/etc/sing-box/config.json`
- systemd 服务：`/etc/systemd/system/sing-box-anytls.service`
- Alpine OpenRC 服务：`/etc/init.d/sing-box-anytls`
- BBR/TCP 调优：`/etc/sysctl.d/99-anytls-tuning.conf`
- TLS 证书和私钥：`/etc/anytls/server.crt`、`/etc/anytls/server.key`
- acme.sh：默认安装在 `/root/.acme.sh`，证书续签和安装路径由 acme.sh 维护。
- swap 建议：`/etc/anytls/swap-plan.env`
- swap 一键脚本：`/etc/anytls/swap-apply-plan.sh`
- 导出目录：`/etc/anytls/exports`

## 规则配置

默认规则等同于：

```bash
sudo bash /opt/anytls-script/anytls-install.sh --yes --domain your-domain.example --rules safe
```

`safe` 会阻断：

- `geoip-cn`
- `geosite-geolocation-cn`
- `geosite-bittorrent`
- `protocol=bittorrent`

只阻断 CN：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --rules block-cn
```

只阻断 BitTorrent：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --rules block-bt
```

不启用内置阻断规则：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example --rules none
```

添加完整自定义 rule_set：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- \
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
- `v2rayn-share.txt`：给 v2RayN 导入的分享链接，默认包含 `fp=chrome` 和 `alpn=h2,http/1.1`。
- `clash-verge.yaml`：给 Clash Verge Rev 使用的 YAML。
- `sing-box-client.json`：sing-box 客户端 outbound 示例。
- `subscription.txt`：包含分享链接和客户端 JSON 路径。

查看分享链接：

```bash
sudo cat /etc/anytls/exports/share-link.txt
```

把 `anytls://...` 链接复制到 Clash Verge Rev 或 v2RayN 中导入即可。

## 证书策略

默认行为：

```bash
curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example
```

安装器会在缺少证书时安装或复用 acme.sh，执行 standalone HTTP-01 签发，并把 fullchain 和私钥安装到：

- `/etc/anytls/server.crt`
- `/etc/anytls/server.key`

acme.sh 会保存 `--install-cert` 部署配置；后续续签成功时会自动重新安装证书并重启 `sing-box-anytls` 服务。

如果已有证书，可以直接指定路径：

```bash
sudo bash /opt/anytls-script/anytls-install.sh --yes \
  --domain your-domain.example \
  --cert-file /path/to/fullchain.pem \
  --key-file /path/to/private.key
```

只有测试、临时 IP、内网环境等无法使用 ACME 的场景才使用：

```bash
sudo bash /opt/anytls-script/anytls-install.sh --yes --domain 203.0.113.10 --self-signed
```

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

## 手动保留方案

正常情况下不需要手动安装 sing-box，也不需要手动 clone 仓库。下面只作为网络受限、自动安装失败或需要审计脚本时的保留方案。

### 手动安装 sing-box

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

确认安装：

```bash
sing-box version
```

### 手动拉取仓库并安装

```bash
git clone https://github.com/Redstonexs/anytls-script.git
cd anytls-script
sudo bash anytls-install.sh --domain your-domain.example
```

只查看计划，不写入系统：

```bash
sudo bash anytls-install.sh --dry-run --domain your-domain.example --no-color
```

## 注意事项

- 管道安装前可以先在浏览器打开 `install.sh` 查看内容。
- 默认不会生成自签证书；缺少证书时会使用 acme.sh 为域名签发证书。
- ACME 签发失败时请检查 DNS、TCP `80` 入站、安全组、防火墙和端口占用。
- 导出的分享链接包含连接密码，请不要公开发布。
- 如果 VPS 已有 swap，脚本不会创建新的 swap。
- `install.sh` 默认会自动追加 `--yes`。需要交互确认时传 `--interactive`。
- 默认 ALPN 是 `h2,http/1.1`，默认 fingerprint 是 `chrome`；可通过 `--alpn` 和 `--fingerprint` 覆盖。

## 参考

- sing-box Linux 安装文档：https://github.com/sagernet/sing-box/blob/v1.13.14/docs/installation/package-manager.md
- sing-box AnyTLS inbound：https://github.com/sagernet/sing-box/blob/v1.13.14/docs/configuration/inbound/anytls.md
- sing-box AnyTLS outbound：https://github.com/sagernet/sing-box/blob/v1.13.14/docs/configuration/outbound/anytls.md
