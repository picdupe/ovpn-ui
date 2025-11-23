// 通用JavaScript功能

// 显示消息提示
function showMessage(message, type = 'info') {
    const messageDiv = document.createElement('div');
    messageDiv.className = `message message-${type}`;
    messageDiv.textContent = message;
    
    // 添加到页面顶部
    document.body.insertBefore(messageDiv, document.body.firstChild);
    
    // 3秒后自动消失
    setTimeout(() => {
        messageDiv.remove();
    }, 3000);
}

// 格式化日期
function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleString('zh-CN');
}

// 验证邮箱格式
function isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

// 验证密码强度
function isStrongPassword(password) {
    return password.length >= 8;
}

// 加载中状态
function setLoading(button, isLoading) {
    if (isLoading) {
        button.disabled = true;
        button.innerHTML = '<span class="loading-spinner"></span> 处理中...';
    } else {
        button.disabled = false;
        button.innerHTML = button.getAttribute('data-original-text');
    }
}

// 标签页切换
function showTab(tabName) {
    // 隐藏所有标签内容
    document.querySelectorAll('.tab-content').forEach(tab => {
        tab.classList.remove('active');
    });
    
    // 移除所有标签按钮的active类
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    
    // 显示选中的标签内容
    document.getElementById(`${tabName}-tab`).classList.add('active');
    
    // 激活选中的标签按钮
    event.target.classList.add('active');
    
    // 加载对应标签的数据
    loadTabData(tabName);
}

// 加载标签数据
async function loadTabData(tabName) {
    try {
        const response = await fetch('/api/users');
        const users = await response.json();
        
        let filteredUsers = users;
        if (tabName === 'pending') {
            filteredUsers = users.filter(user => user.status === 'pending');
        } else if (tabName === 'approved') {
            filteredUsers = users.filter(user => user.status === 'approved');
        }
        
        renderUsersList(`${tabName}-users-list`, filteredUsers);
    } catch (error) {
        console.error('加载用户数据失败:', error);
        showMessage('加载用户数据失败', 'error');
    }
}

// 渲染用户列表
function renderUsersList(containerId, users) {
    const container = document.getElementById(containerId);
    
    if (users.length === 0) {
        container.innerHTML = '<p class="no-data">暂无数据</p>';
        return;
    }
    
    container.innerHTML = users.map(user => `
        <div class="user-card">
            <div class="user-info-row">
                <div>
                    <strong>${user.username}</strong>
                    <span class="user-email">${user.email}</span>
                </div>
                <span class="user-status status-${user.status}">${getStatusText(user.status)}</span>
            </div>
            <div class="user-details">
                <div>创建时间: ${formatDate(user.created_at)}</div>
                ${user.ovpn_username ? `<div>OpenVPN用户: ${user.ovpn_username}</div>` : ''}
                ${user.max_devices ? `<div>最大设备数: ${user.max_devices}</div>` : ''}
            </div>
            <div class="user-actions">
                ${user.status === 'pending' ? `
                    <button class="btn-primary btn-sm" onclick="openApproveModal(${user.id}, '${user.username}')">审核</button>
                ` : ''}
                ${user.status === 'approved' ? `
                    <button class="btn-secondary btn-sm" onclick="generateDownloadLink('${user.username}')">下载配置</button>
                ` : ''}
                <button class="btn-danger btn-sm" onclick="deleteUser(${user.id})">删除</button>
            </div>
        </div>
    `).join('');
}

// 获取状态文本
function getStatusText(status) {
    const statusMap = {
        'pending': '待审核',
        'approved': '已开通',
        'rejected': '已拒绝',
        'suspended': '已暂停'
    };
    return statusMap[status] || status;
}