[English](README.md) | Русский

# deepseek-harness.nix

Nix-флейк с пакетом [DeepSeek Harness (`dsh`)](https://github.com/deepseek-ai/deepseek-harness) — CLI и Web UI.

Пакет устанавливает официальный npm-релиз `@deepseek-ai/dsh` вместе с официальной сборкой Node.js и даёт один бинарник `dsh`.

## Почему npm-релиз, а не архив GitHub

Все релизы в [deepseek-ai/deepseek-harness/releases](https://github.com/deepseek-ai/deepseek-harness/releases) — это теги без вложений: GitHub API отдаёт `assets: 0`. Архив `tar.gz` в блоке «Assets» — автоматически сгенерированный снимок исходников тега: ~39 МБ, 23 112 файлов TypeScript-монорепозитория на pnpm, без артефактов сборки, без `node_modules` и без нативных бинарников. Его использование означало бы воспроизведение всей upstream-сборки workspace в песочнице Nix.

`@deepseek-ai/dsh` — официальная опубликованная сборка того же релиза: скомпилированный JS плюс 90 зависимостей `@deepseek-ai/dsh-*`, включая предсобранные нативные аддоны под каждую платформу (`node-addon-system-linux-x64`, `node-addon-require-builtin-linux-x64-gnu`, `node-pty`, `koffi`, `sharp` и т.д.).

## Почему официальная сборка Node.js

DSH стартует через `node-addon-require-builtin` — нативный аддон, который находит внутренний загрузчик модулей Node, сканируя сам бинарник Node. Сборку из nixpkgs он не распознаёт:

```
dsh: host preparation failed: node-addon-require-builtin unsupported: Unsupported/no-getter
  (x64 sysv getter is not a recognized this->field accessor)
```

Сборка той же версии с [nodejs.org](https://nodejs.org/dist) запускается нормально. Поэтому рантайм скачивается с nodejs.org и закреплён в `sources.json` (`node.version`, URL и хеш на каждую платформу). Не заменяйте его на `pkgs.nodejs_24` — пакет упадёт при старте.

## Почему не Bun

Bun не может запустить `dsh`. Два независимых блокера:

1. Тот же аддон `node-addon-require-builtin` требует внутренностей Node/V8. Под `bun 1.3.13` он падает с `No usable native binding found for node-addon-require-builtin-linux-x64-gnu`.
2. Бэкенд хранилища (`@deepseek-ai/dsh-storage-sqlite`) импортирует `node:sqlite`, которого в Bun нет.

Флаг `--version` под Bun отвечает, но любой реальный запуск профиля завершается ошибкой. Обходного переключателя нет — нужны изменения в upstream.

## Поддерживаемые платформы

| Система          | Статус                                                              |
|------------------|---------------------------------------------------------------------|
| `x86_64-linux`   | апстрим-рантайм проверен вручную, `nix build` не доведён до конца    |
| `aarch64-linux`  | не проверено                                                        |
| `x86_64-darwin`  | не проверено                                                        |
| `aarch64-darwin` | не проверено                                                        |

## Использование

Запуск без установки:

```sh
nix run github:smykoff/deepseek-harness.nix
```

Установка в профиль пользователя:

```sh
nix profile install github:smykoff/deepseek-harness.nix
```

Запуск Web UI (по умолчанию `http://127.0.0.1:3080`):

```sh
dsh web
```

### NixOS (flakes)

```nix
{
  inputs.dsh.url = "github:smykoff/deepseek-harness.nix";

  outputs = { nixpkgs, dsh, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [ dsh.packages.${pkgs.system}.default ];
        })
      ];
    };
  };
}
```

Или через оверлей:

```nix
nixpkgs.overlays = [ dsh.overlays.default ];
environment.systemPackages = [ pkgs.dsh ];
```

### Home Manager

```nix
home.packages = [ inputs.dsh.packages.${pkgs.system}.default ];
```

## Примечания

- Обёртка добавляет в `PATH` `node`, `npm`, `npx` (из закреплённой официальной сборки Node.js), `bash`, coreutils, `git`, `openssh` и `which` — установка плагинов и работа инструментов идут из коробки.
- Нативные аддоны патчатся `autoPatchelfHook`. В npm-дереве лежат бинарники и для других платформ, поэтому включён `autoPatchelfIgnoreMissingDeps`.
- Install-скрипты отключены (`--ignore-scripts`): все зависимости используются через предсобранные бинарники. Бит исполнения у `spawn-helper` из `node-pty` восстанавливается при установке — так же, как это делает upstream в postinstall.
- Состояние живёт в `$DSH_HOME` (по умолчанию в домашнем каталоге), а не в Nix store.

### Скачиваемые бинарники (Linux)

Часть компонентов DSH докачивает в рантайме (например, движок Office и Python-окружение для Python SDK). В NixOS для них нужен слой совместимости динамического загрузчика:

```nix
programs.nix-ld.enable = true;
programs.nix-ld.libraries = with pkgs; [ stdenv.cc.cc.lib zlib openssl ];
```

## Обновление

`sources.json` — единственный источник версии: `version`, `npmDepsHash` и пины рантайма Node.js. Точный набор зависимостей лежит в `npm/package.json` и `npm/package-lock.json`.

```sh
bash scripts/update.sh                      # следовать тегу `latest` в npm
bash scripts/update.sh --node-version 24.x  # дополнительно перепинить Node.js
```

Скрипт определяет новую версию, перегенерирует lockfile, вычисляет `npmDepsHash` из ошибки несовпадения хеша при первой сборке и затем собирает пакет. Ежедневный workflow (`.github/workflows/update.yml`) запускает его и коммитит результат.

Пин Node.js обновляется вручную осознанно: с нативным аддоном совместима только официальная сборка, и новый релиз Node.js стоит предварительно проверить.
