# DC 地址：种子与 `help.getConfig`（M7 / D-33）

结论：iOS **不会**把 `Tellomi/tellomi-server.json` 锁成永久地址。种子只在该数据中心还没有持久地址集时使用。已登录客户端拿到 `help.getConfig` 里能通过 `inet_pton` 的地址后，会按数据中心 id 整表替换并写入钥匙串；之后的连接用这份表。主机名、空列表、某一只 DC 过滤后一个 IP 都不剩，都不会写入。没有任何 Tellomi 补丁在每次启动时把种子写回持久表。

生产上这份表今天是空的，所以已安装的客户端目前仍停在种子上。把地址写进服务端配置并重启 `bff` 之后，不升级的 iOS 会改连新 IP。下面的测试 IP 步骤用来确认这一点。本文只覆盖 iOS 仓库；安卓不在这个检出里。

核对日期 2026-11-03。服务端源码是 [tellomi/teamgram-server](https://github.com/tellomi/teamgram-server) `bf02a4b721c3a0350a7bf2727e89119cd1f3e5fb`。没有对线上进程发 `help.getConfig`。

## 种子只作回落

`Tellomi/tellomi-server.json` 的 `seeds.production` / `seeds.testing` 是数据中心 `1` → `api.tellomi.cn`，端口 `seed_port` `10443`。`seed_address_a_record`（`8.137.39.82`）不参与拨号。生成头 `TellomiServerConfigJSON.h` 在每次创建网络时被读出来，调用 `setSeedAddressSetForDatacenterWithId`（`submodules/TelegramCore/Sources/Network/Network.swift`）：

```swift
let seedPort = TellomiSeedPort()
for (id, ips) in TellomiSeedAddresses(testingEnvironment) {
    context.setSeedAddressSetForDatacenterWithId(id.intValue, seedAddressSet: ...)
}
```

这次写入只进内存里的 `_datacenterSeedAddressSetById`，不进钥匙串（`MTContext` `setSeedAddressSetForDatacenterWithId:`）。随后 `context.keychain = keychain` 才从钥匙串组 `persistent`、键 `datacenterAddressSetById` 装入持久表。

取地址时持久表优先。持久表缺这只 DC，或这只 DC 的列表是空的，才退回种子（`MTContext` `addressSetForDatacenterWithId:`）：

```objc
MTDatacenterAddressSet *addressSet = _datacenterAddressSetById[@(datacenterId)];
if (addressSet != nil && addressSet.addressList.count != 0) {
    result = addressSet;                 // 钥匙串里的 dc_options
} else {
    result = _datacenterSeedAddressSetById[@(datacenterId)];
}
```

`disable_telegram_backup_discovery` 为真时，`initializedNetwork` 不安装 `MTBackupAddressSignals`，因此不会用 `apv3.stel.com` 换掉种子。

连接失败后的探测会把种子**追加**到当前地址集后面再试（`transportSchemeForDatacenterWithIdRequired:`）。这不改写钥匙串里的持久表。新 IP 能通时，正常连接用的是持久表里的地址；新 IP 不通时，探测仍能退回 `api.tellomi.cn`。

## 已登录客户端采纳 `dc_options`

`Account` 初始化末尾调用 `restartConfigurationUpdates()`，立刻拉一次 `help.getConfig`，之后每小时一次（`managedConfigurationUpdates` 里 `suspendAwareDelay` 一小时再 `restart`）。未登录的 `UnauthorizedAccount` 不跑这条。

`submodules/TelegramCore/Sources/State/ManagedConfigurationUpdates.swift` 把每个 `dcOption` 交给 `tellomiAcceptedDatacenterAddresses`（`TellomiDcAddress.swift`）。发现传输用的 `Serialization.requestDatacenterAddress` 走同一个函数。规则与安卓 `tellomiAcceptDcAddress` 相同：端口必须在 1–65535，并且 `ipv6` 标志选中的地址族要让 `inet_pton` 成功。通过的地址按 DC id 整表替换：

```swift
let addressList = tellomiAcceptedDatacenterAddresses(tellomiDcOptionInputs(dcOptions))
if !addressList.isEmpty {
    network.context.performBatchUpdates {
        for (id, list) in addressList {
            let addresses = list.map { MTDatacenterAddress(ip: $0.host, port: $0.port, /* flags, secret */) }
            network.context.updateAddressSetForDatacenter(
                withId: id,
                addressSet: MTDatacenterAddressSet(addressList: addresses),
                forceUpdateSchemes: false)
        }
    }
}
```

`updateAddressSetForDatacenterWithId:forceUpdateSchemes:` 用这只 DC 的新列表换掉旧列表，并写回钥匙串。下面几种情况**不会**调用它，已保存的地址或种子留着：

- `dc_options` 为空。
- 某一只 DC 的地址全是主机名（例如 `api.tellomi.cn`），或端口非法，或 IPv4/IPv6 标志和字面量对不上。过滤后该 DC 不在结果里。
- 其它 DC 里还有合法 IP 时，只替换那些 DC。主机名被丢掉，不和 IP 混着写入。

某一只 DC 的列表为空时，`MTDiscoverDatacenterAddressAction` `getConfigSuccess:` 同样不调用更新。因此一条坏的空配置或主机名配置不会把客户端砖死；它只是留在上一次成功的地址（或种子）上。同一地址族里重复的 `主机+端口` 只留第一条。

`forceUpdateSchemes` 这里是 `false`。持久表原先就是空的时（按当前这份空 `dc_options` 连过的客户端就是这样），`previousAddressSetWasEmpty` 为真，`MTProto` `contextDatacenterTransportSchemesUpdated:shouldReset:` 会当场拆掉传输并按新表重连。持久表里已经有上一份非空地址时，当前这条连接要等下次进程启动，或等这条连接失败后的重探，才改用新 IP。启动时方案来自持久表；种子主机名对不上表里的 IP，不会被当成已选方案留下。

iOS 从 `dcOption` 读的标志位：bit 0 是否按 IPv6 做 `inet_pton`、bit 1 媒体、bit 2 仅 TCP、bit 3 CDN、bit 4 代理优先，以及可选 `secret`。**不读** `this_port_only`（bit 5）。发现传输时，除了声明的端口，还会额外探 80 和 5222（`MTDiscoverConnectionSignals` `alternatePortsForProxySettings:`）；声明端口没有那 5 秒附加延迟。正常建连用的是声明端口。唯一一条地址不要标 `media_only`，否则主连接会把该地址滤掉。

## 和安卓 #52 的差别

安卓 `TELLOMI_LOCK_DC_ADDRESSES` 默认改为 `false` 之后，`help.getConfig` 才会 `replaceAddresses`。iOS 没有这把锁：`tellomi-server.json` 只提供种子，`setSeedAddressSetForDatacenterWithId` 不写钥匙串。持久表非空时种子不会盖回去。这次补上的是安卓在解锁时加的过滤，以前 iOS 会把 `dc_options` 里的主机名原样写进持久表。

| | 安卓 #52 | iOS |
| --- | --- | --- |
| 种子会不会锁死 | 不会。某个 DC 已经在 `tgnet.dat` 里时，构建期种子不覆盖它。 | 不会。种子只在持久表缺这只 DC 或列表为空时使用。 |
| 空 `dc_options` | 不替换，也不为这次配置写地址。 | 不调用 `updateAddressSet`。 |
| 主机名 | `inet_pton` 失败就丢掉。该地址族一个不剩则不替换。 | 同样丢掉。这只 DC 一个 IP 都不剩则不替换。 |
| 合法 IP | 替换对应地址族。 | 替换这只 DC 的整张表（iOS 一张表装下四个族）。新表里只有通过过滤的地址。 |
| 未登录 | 介绍页会请求 `help.getConfig`。 | `UnauthorizedAccount` 不跑这条轮询。登录成功后的 `Account` 启动时立刻请求。登录流程本身没有改。 |
| 种子形式 | 构建期种子是 IP（`8.137.39.82`），因为拨号只用 `inet_pton`。 | 种子仍是 `api.tellomi.cn`，`GCDAsyncSocket` 用 `getaddrinfo` 解析。它不经过上面的过滤，也不会被 `getConfig` 写进持久表。 |

安卓按 IPv4、IPv6、媒体 IPv4、媒体 IPv6 四个族分别替换：某一族过滤后为空就留着该族的旧地址。iOS 的持久表是每只 DC 一张列表，有合法 IP 时整张换成这些 IP。Tellomi 只有 DC 1 的 IPv4，两边结果一样。不要靠「只下发 IPv6、旧的 IPv4 还留着」这种安卓行为。

## 生产 `help.getConfig` 现在下发什么

`bff` 的工作目录是 `/app/bin`（镜像把 `teamgramd/` 拷到 `/app/`，入口 `cd /app/bin` 再跑 `runall-docker.sh`）。`help.getConfig` 在进程 `init` 里读一次 `./config.json`，也就是仓库里的 `teamgramd/bin/config.json`。`docker-compose.yaml` 没有把这个文件挂成卷。处理函数克隆这份配置后只改日期、过期时间、`me_url_prefix`、语言和默认反应，**不填** `dc_options`。

当前文件：

| 字段 | 值 | 说明 |
| --- | --- | --- |
| `dc_options` | `[]` | 客户端不会更新地址。已安装的 iOS 继续用种子 `api.tellomi.cn:10443`。 |
| `this_dc` | `1` | 与种子、客户端默认 DC 一致。 |
| `dc_txt_domain_name` | `apv2.stel.com` | 仍是 Telegram 的 TXT 域名。iOS 不读这个字段；备用发现已被 `disable_telegram_backup_discovery` 关掉。安卓若还拿它做备用发现，会指向 Telegram。 |
| `webfile_dc_id` | `4` | 没有任何 DC 4 的地址。iOS 会把 4 存成网页文件所在 DC。主连接仍是 DC 1，但网页文件可能去探测一个不存在的 DC。 |

gnetway（`teamgramd/etc/gnetway.yaml`，Docker 实际用 `teamgramd/etc2/gnetway.yaml` 的同一组监听）在 `0.0.0.0:10443` 和 `0.0.0.0:5222` 上收 TCP，WebSocket 在 `11443`。公网地址是 `8.137.39.82`。这些端口**没有**写进 `dc_options`。

编码还有一个坑：`DcOption.Encode` 在 `predicate_name` 不是 `dcOption` 时直接报错，`TLConfig` 编码会把失败的条目从 vector 里丢掉（不写字节，只把个数减掉）。漏写 `predicate_name` 的配置，线上看起来仍是空的 `dc_options`。

要让不升级的客户端改 IP，必须把 **IP 字面量**写进 `dc_options`（硬规则 2：DC 用 IP:端口，`inet_pton`；域名留给网站）。不要写 `api.tellomi.cn`。然后重启 `bff`（`init` 只读一次；改运行中的文件而不重启进程不会生效）。容器按未修改的镜像重建会回到空列表。

## 用测试 IP 验证

测试 IP 必须能完成 MTProto（同一台 gnetway，或转到 `8.137.39.82:10443` 的地址）。黑洞地址不会留下“已经连上新 IP”的证据；失败后的探测还会去试种子，客户端最终仍能连上生产，只是每次都会先撞测试 IP。

1. 校验 JSON 之后，把运行中容器的 `/app/bin/config.json` 里 `data2.dc_options` 换成例如：

   ```json
   [
     {
       "predicate_name": "dcOption",
       "id": 1,
       "ip_address": "<测试 IP>",
       "port": 10443,
       "this_port_only": true
     }
   ]
   ```

   `this_port_only` 给会读这个标志的客户端（含安卓）。iOS 忽略它，发现阶段仍会多探 80 和 5222。抓包时看到这两个端口是探测，不是地址集被改写。5222 在 gnetway 上是开的，80 不在监听列表里。10443 没有附加延迟，它先通就会被选中。不要给这一条设 `media_only`。

2. 重启容器，使 `bff` 重新读配置。`config.json` 非法时 `init` 会 panic，接口起不来。

3. 用**已经装好、不用升级**的 iOS，登录状态前台打开一次（或杀掉再开）。`Account` 启动时会立刻发 `help.getConfig`。今天的客户端持久表是空的，所以同一次会话就会按新表重连。

4. 在测试 IP 的 10443 上确认来自这台手机的 TCP。地址集里不应再是种子主机名。杀掉进程再打开，仍应打到测试 IP：钥匙串里的表还在，种子没有盖回去。

5. 把 `dc_options` 改回 `[]` 并重启 `bff`。已经采纳过测试 IP 的客户端**保持**该 IP，空列表不会擦掉它。测试机要回到种子，需删除 App（或清掉钥匙串键 `persistent:datacenterAddressSetById`）。测试 IP 停止应答后，失败探测会再试 `api.tellomi.cn`，所以生产仍可连上，但每次启动都会先试测试 IP。
