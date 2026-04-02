#!/bin/bash
cd "$(dirname "$0")"

echo "🔍 Проверяю локальные изменения..."
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️  Есть незакоммиченные изменения. Сохраняю их временно..."
  git stash
  STASHED=1
else
  STASHED=0
fi

echo "⬇️  Получаю изменения с GitHub..."
git pull github main

if [ "$STASHED" = "1" ]; then
  echo "♻️  Восстанавливаю локальные изменения..."
  git stash pop
fi

echo ""
echo "✅ Готово! Локальная директория обновлена."
read -p "Нажми Enter для закрытия..."
