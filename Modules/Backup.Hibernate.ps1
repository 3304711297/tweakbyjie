# Backup.Hibernate.ps1 - 系统休眠与快速启动原始状态快照与恢复
# 核心实现由 Modules/Hibernate.ps1 统一承载

if (-not (Get-Command Ensure-HibernateBackup -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot/Hibernate.ps1"
}
