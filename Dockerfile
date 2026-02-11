# ベースイメージとしてNode.js 20を使用
FROM node:20

# ビルド時引数：タイムゾーン
ARG TZ
# 環境変数としてタイムゾーンを設定
ENV TZ="$TZ"

# ビルド時引数：Claude Codeのバージョン（デフォルトは最新版）
ARG CLAUDE_CODE_VERSION=latest

# 基本的な開発ツールとネットワーク管理ツールをインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \          # ページャー（ファイルの閲覧）
  git \           # バージョン管理システム
  procps \        # プロセス管理ツール（ps、topなど）
  sudo \          # 管理者権限でコマンド実行
  fzf \           # ファジーファインダー（ファイル検索）
  zsh \           # Zシェル（高機能なシェル）
  man-db \        # マニュアルページ
  unzip \         # ZIP解凍ツール
  gnupg2 \        # GPG暗号化ツール
  gh \            # GitHub CLI
  iptables \      # ファイアウォール管理ツール
  ipset \         # IPアドレスセット管理ツール
  iproute2 \      # ネットワーク設定ツール
  dnsutils \      # DNS関連ツール（digコマンドなど）
  aggregate \     # IPアドレス集約ツール
  jq \            # JSON処理ツール
  nano \          # テキストエディタ（シンプル）
  vim \           # テキストエディタ（高機能）
  && apt-get clean && rm -rf /var/lib/apt/lists/*  # キャッシュ削除（イメージサイズ削減）

# npmのグローバルパッケージ用ディレクトリを作成し、nodeユーザーに権限を付与
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

# デフォルトユーザー名を設定
ARG USERNAME=node

# Bashコマンド履歴を永続化するための設定
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \         # 履歴保存用ディレクトリ作成
  && touch /commandhistory/.bash_history \  # 履歴ファイル作成
  && chown -R $USERNAME /commandhistory     # nodeユーザーに所有権を付与

# 開発コンテナ内であることを示す環境変数を設定
ENV DEVCONTAINER=true

# ワークスペースとClaude設定用ディレクトリを作成し、権限を設定
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

# 作業ディレクトリを/workspaceに設定
WORKDIR /workspace

# Git Deltaのバージョンを指定（Git差分をより見やすく表示するツール）
ARG GIT_DELTA_VERSION=0.18.2
# Git Deltaをダウンロードしてインストール
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"  # debファイルを削除

# 以降の処理をnodeユーザーで実行（root権限から切り替え）
USER node

# npmグローバルパッケージのインストール先を設定
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
# パスにnpmグローバルパッケージのbinディレクトリを追加
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# デフォルトシェルをzshに設定
ENV SHELL=/bin/zsh

# デフォルトエディタをnanoに設定
ENV EDITOR=nano
ENV VISUAL=nano

# Zsh in Dockerのバージョンを指定（Zsh設定の自動セットアップツール）
ARG ZSH_IN_DOCKER_VERSION=1.2.0
# Zshの設定とプラグインをインストール
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \    # gitプラグインを有効化
  -p fzf \    # fzfプラグインを有効化
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \  # fzfキーバインド設定
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \    # fzf補完設定
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \  # 履歴設定
  -x  # powerlevel10kテーマを無効化

# Claude Code CLIをグローバルインストール
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}


# ファイアウォール初期化スクリプトをコンテナ内にコピー
COPY init-firewall.sh /usr/local/bin/
# 一時的にrootユーザーに切り替え（スクリプトに実行権限を付与するため）
USER root
# スクリプトに実行権限を付与し、nodeユーザーがsudoで実行できるように設定
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall  # sudoers設定ファイルの権限を適切に設定
# nodeユーザーに戻す
USER node