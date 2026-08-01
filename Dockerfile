# syntax=docker/dockerfile:1

# =============================================================
# nginx + ngx_http_geoip2_module
#
# 构建:  docker build -t nginx-geoip2 .
# 运行:  docker run -d -p 80:80 \
#          -v /host/GeoLite2-Country.mmdb:/etc/nginx/geoip/GeoLite2-Country.mmdb:ro \
#          nginx-geoip2
#
# 构建参数:
#   NGINX_VERSION           nginx 版本（必须与官方镜像 tag 一致），默认 1.30.4
#   GEOIP2_MODULE_VERSION   ngx_http_geoip2_module 版本，默认 3.4
# =============================================================

ARG NGINX_VERSION=1.30.4

# ---------- Stage 1: 编译 geoip2 动态模块 ----------
FROM nginx:${NGINX_VERSION} AS builder

ARG NGINX_VERSION
ARG GEOIP2_MODULE_VERSION=3.4

# 编译工具链与依赖
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libmaxminddb-dev \
        libpcre2-dev \
        libssl-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 下载与镜像完全一致的 nginx 源码
RUN curl -fsSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o /tmp/nginx.tar.gz \
    && mkdir -p /usr/src \
    && tar -xzf /tmp/nginx.tar.gz -C /usr/src \
    && mv "/usr/src/nginx-${NGINX_VERSION}" /usr/src/nginx

# 获取 ngx_http_geoip2_module 源码（默认 tag 3.4，可传 master 使用最新代码）
RUN git clone --depth 1 --branch "${GEOIP2_MODULE_VERSION}" \
        https://github.com/leev/ngx_http_geoip2_module.git \
        /usr/src/ngx_http_geoip2_module

WORKDIR /usr/src/nginx

# 复用官方镜像的 configure 参数（保证 ABI 兼容），追加 geoip2 动态模块
# 注意：nginx -V 输出的参数带引号（如 --with-cc-opt='-g -O2 ...'），
# 需要用 eval 重新解析引号，否则空格会被拆成独立参数导致 configure 报错
RUN CONFARGS="$(nginx -V 2>&1 | sed -n 's/^configure arguments: //p')" \
    && eval "./configure ${CONFARGS} --add-dynamic-module=/usr/src/ngx_http_geoip2_module" \
    && make -j"$(nproc)" modules

# ---------- Stage 2: 运行时镜像 ----------
FROM nginx:${NGINX_VERSION}

# 复制编译好的动态模块到官方模块目录
COPY --from=builder /usr/src/nginx/objs/ngx_http_geoip2_module.so \
     /usr/lib/nginx/modules/ngx_http_geoip2_module.so

# 运行时依赖 libmaxminddb，并准备数据库挂载目录
RUN apt-get update \
    && apt-get install -y --no-install-recommends libmaxminddb0 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/nginx/geoip

# 配置文件：启用模块 + 示例配置
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/geoip2.example.conf /etc/nginx/conf.d/geoip2.example.conf

STOPSIGNAL SIGQUIT

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
