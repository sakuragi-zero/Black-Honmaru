# ベースイメージとしてNode.js 20を使用
FROM node:20

# ビルド時引数：タイムゾーン
ARG TZ
# 環境変数としてタイムゾーンを設定
ENV TZ="$TZ"

# 基本的な開発ツールとネットワーク管理ツールをインストール
# less:      ページャー（ファイルの閲覧）
# git:       バージョン管理システム
# procps:    プロセス管理ツール（ps、topなど）
# sudo:      管理者権限でコマンド実行
# fzf:       ファジーファインダー（ファイル検索）
# zsh:       Zシェル（高機能なシェル）
# man-db:    マニュアルページ
# unzip:     ZIP解凍ツール
# gnupg2:    GPG暗号化ツール
# gh:        GitHub CLI
# iptables:  ファイアウォール管理ツール
# ipset:     IPアドレスセット管理ツール
# iproute2:  ネットワーク設定ツール
# dnsutils:  DNS関連ツール（digコマンドなど）
# aggregate: IPアドレス集約ツール
# jq:        JSON処理ツール
# nano:      テキストエディタ（シンプル）
# vim:       テキストエディタ（高機能）
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# /usr/local/shareディレクトリの権限をnodeユーザーに付与
RUN chown -R node:node /usr/local/share

# デフォルトユーザー名を設定
ARG USERNAME=node

# Bashコマンド履歴を永続化するための設定
# 1. 履歴保存用ディレクトリを作成
# 2. 履歴ファイルを作成
# 3. nodeユーザーに所有権を付与
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# 開発コンテナ内であることを示す環境変数を設定
ENV DEVCONTAINER=true

# ワークスペースとClaude設定用ディレクトリを作成し、権限を設定
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

# 作業ディレクトリを/workspaceに設定
WORKDIR /workspace

# Git Deltaのバージョンを指定（Git差分をより見やすく表示するツール）
ARG GIT_DELTA_VERSION=0.18.2
# Git Deltaをダウンロードしてインストール（debファイルは後で削除）
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# 以降の処理をnodeユーザーで実行（root権限から切り替え）
USER node

# デフォルトシェルをzshに設定
ENV SHELL=/bin/zsh

# デフォルトエディタをnanoに設定
ENV EDITOR=nano
ENV VISUAL=nano

# Zsh in Dockerのバージョンを指定（Zsh設定の自動セットアップツール）
ARG ZSH_IN_DOCKER_VERSION=1.2.0
# Zshの設定とプラグインをインストール
# -p git:  gitプラグインを有効化
# -p fzf:  fzfプラグインを有効化
# -a:      追加のシェル設定（fzfキーバインド、補完、履歴の永続化）
# -x:      powerlevel10kテーマを無効化
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Claude Codeをネイティブインストーラーでインストール（公式推奨方法）
RUN curl -fsSL https://claude.ai/install.sh | bash
# Claude Codeのインストール先（~/.local/bin）をPATHに追加
ENV PATH="/home/node/.local/bin:$PATH"

# ファイアウォール初期化スクリプトをコンテナ内にコピー
COPY init-firewall.sh /usr/local/bin/
# 一時的にrootユーザーに切り替え（スクリプトに実行権限を付与するため）
USER root
# スクリプトに実行権限を付与し、nodeユーザーがsudoで実行できるように設定
# sudoers設定ファイルの権限を0440に設定（セキュリティ要件）
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
# nodeユーザーに戻す
USER node