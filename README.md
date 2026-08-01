# nginx + ngx_http_geoip2_module

基于官方 nginx 镜像，动态编译 [leev/ngx_http_geoip2_module](https://github.com/leev/ngx_http_geoip2_module)（MaxMind GeoIP2 模块）。构建出的镜像开箱即用，模块已加载，只需挂载 `.mmdb` 数据库。

## 数据库选择

项目目录里有两个 Country 库，用途不同：

| 文件 | 说明 |
| --- | --- |
| `Country-All.mmdb` | 全量 GeoLite2-Country（2026-07-10 构建），IPv4 + IPv6 全球覆盖。**做"只允许中国 IP"请用这个**：中国 IP 返回 `CN`，国外 IP 返回对应国家码，内网/保留 IP 无记录 |
| `Country.mmdb` | 中国专用精简库（仅 IPv4，约 130KB）。中国 IP 返回 `CN`，国外 IP 无记录；但缺少部分中国段（如 223.118–127.x、101.197.x 等）且**不含 IPv6**，用它会误伤这些用户 |

本项目所有示例均以 `Country-All.mmdb` 为准。

## 构建

```bash
docker build -t nginx-geoip2 .
```

可用构建参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `NGINX_VERSION` | `1.30.4` | nginx 版本，需与官方镜像 tag 一致 |
| `GEOIP2_MODULE_VERSION` | `3.4` | geoip2 模块版本；若新版本 nginx 编译报错，可传 `master` 使用最新代码 |

```bash
# 示例：换用其他 nginx 版本
docker build --build-arg NGINX_VERSION=1.29.6 -t nginx-geoip2 .
```

## 运行

```bash
docker run -d --name nginx-geoip2 -p 80:80 \
  -v /host/path/Country-All.mmdb:/etc/nginx/geoip/Country-All.mmdb:ro \
  nginx-geoip2
```

## 验证

```bash
curl http://localhost/geoip
# 输出示例：
# country_code=CN
# country_name=China
# city=
```

## 配置说明

- `nginx.conf` 在 main 上下文通过 `load_module` 加载了编译好的模块。
- `conf.d/geoip2.example.conf` 是完整的"只允许中国 IP"配置示例（含变量定义、403 拦截、验证接口）。需要时复制为 `geoip2.conf`：

```bash
docker exec nginx-geoip2 cp /etc/nginx/conf.d/geoip2.example.conf /etc/nginx/conf.d/geoip2.conf
docker exec nginx-geoip2 nginx -s reload
```

规则逻辑：`if ($geoip2_data_country_code !~ ^CN$) { return 403; }` —— 中国 IP 放行；国外 IP、无记录 IP、内网 IP（变量为空）全部返回 403。

## 自动编译（GitHub Actions）

推送到 GitHub 后，[.github/workflows/docker-build.yml](.github/workflows/docker-build.yml) 会自动构建并发布镜像到 GitHub 容器仓库（GHCR）：

- 推送到 `main` → 构建并推送 `ghcr.io/<你的用户名>/nginx-geoip2:latest` 和 `:nginx-1.30.4`
- 打 `v*` 标签（如 `v1.30.4`）→ 额外推送语义化版本标签
- 提 PR → 只做编译验证（含 `nginx -t` 冒烟测试），不推送
- 手动触发（Actions 页面 "Run workflow"）→ 可指定 nginx / geoip2 模块版本重新构建

不需要任何额外密钥：镜像推送到 GHCR，登录凭据用 GitHub 自带的 `GITHUB_TOKEN`。

拉取并运行：

```bash
docker pull ghcr.io/<你的用户名>/nginx-geoip2:latest
docker run -d --name nginx-geoip2 -p 80:80 \
  -v /host/path/Country-All.mmdb:/etc/nginx/geoip/Country-All.mmdb:ro \
  ghcr.io/<你的用户名>/nginx-geoip2:latest
```

## 单独导出模块文件

如果只想把编译好的 `.so` 拿到其他 nginx 使用：

```bash
docker create --name geoip2-extract nginx-geoip2
docker cp geoip2-extract:/usr/lib/nginx/modules/ngx_http_geoip2_module.so .
docker rm geoip2-extract
```

注意：动态模块与 nginx 主程序版本严格绑定（本镜像为 1.30.x，且官方镜像编译时已带 `--with-compat`），跨版本使用可能加载失败。
