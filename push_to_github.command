#!/bin/bash
cd "$(dirname "$0")"

echo "📦 Проверяю изменения..."
git add -A

if git diff --cached --quiet; then
  echo "✅ Нет изменений для коммита."
else
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
  git commit -m "Auto-sync: $TIMESTAMP"
  echo "✅ Коммит создан."
fi

echo "🚀 Пушу на GitHub..."
git push github main

echo ""
echo "✅ Готово! Репозиторий обновлён."
read -p "Нажми Enter для закрытия..."
