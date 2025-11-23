// 用户管理页面专用JavaScript

// 打开审核模态框
function openApproveModal(userId, username) {
    document.getElementById('approve-user-id').value = userId;
    document.getElementById('approve-username').textContent = username;
    document.getElementById('ovpn-username').value = username;
    document.getElementById('approve-modal').style.display = 'flex';
}

// 关闭审核模态框
function closeApproveModal() {
    document.getElementById('approve-modal').style.display = 'none';
    document.getElementById('approve-form').reset();
}

// 提交审核表单
document.getElementById('approve-form').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const userId = document.getElementById('approve-user-id').value;
    const password = document.getElementById('ovpn-password').value;
    const passwordConfirm = document.getElementById('ovpn-password-confirm').value;
    const ovpnUsername = document.getElementById('ovpn-username').value;
    const maxDevices = document.getElementById('max-devices').value;
    
    // 验证密码
    if (password !== passwordConfirm) {
        alert('密码不匹配');
        return;
    }
    
    if (!isStrongPassword(password)) {
        alert('密码至少需要8位字符');
        return;
    }
    
    const submitButton = this.querySelector('button[type="submit"]');
    const originalText = submitButton.innerHTML;
    submitButton.innerHTML = '<span class="loading-spinner"></span> 开通中...';
    submitButton.disabled = true;
    
    try {
        const response = await fetch(`/api/users/${userId}/approve`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                ovpn_username: ovpnUsername,
                password: password,
                max_devices: parseInt(maxDevices)
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            closeApproveModal();
            showMessage('用户开通成功', 'success');
            loadTabData('pending'); // 刷新待审核列表
            loadTabData('approved'); // 刷新已开通列表
        } else {
            alert('开通失败: ' + result.error);
        }
    } catch (error) {
        alert('网络错误: ' + error.message);
    } finally {
        submitButton.innerHTML = originalText;
        submitButton.disabled = false;
    }
});

// 生成下载链接
async function generateDownloadLink(username) {
    try {
        const response = await fetch(`/api/users/${username}/generate_download`, {
            method: 'POST'
        });
        
        const result = await response.json();
        
        if (result.success) {
            // 创建隐藏的下载链接并触发点击
            const link = document.createElement('a');
            link.href = result.download_url;
            link.download = result.actual_filename;
            link.style.display = 'none';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            
            showMessage('配置文件下载开始', 'success');
        } else {
            showMessage('生成下载链接失败', 'error');
        }
    } catch (error) {
        showMessage('网络错误: ' + error.message, 'error');
    }
}

// 删除用户
async function deleteUser(userId) {
    if (!confirm('确定要删除这个用户吗？此操作不可恢复。')) {
        return;
    }
    
    try {
        const response = await fetch(`/api/users/${userId}`, {
            method: 'DELETE'
        });
        
        const result = await response.json();
        
        if (result.success) {
            showMessage('用户删除成功', 'success');
            // 刷新所有标签页
            loadTabData('pending');
            loadTabData('approved');
            loadTabData('all');
        } else {
            showMessage('删除失败', 'error');
        }
    } catch (error) {
        showMessage('网络错误: ' + error.message, 'error');
    }
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 加载待审核用户列表
    loadTabData('pending');
});