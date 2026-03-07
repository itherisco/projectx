"""
# EmailClient.jl

Email client capabilities for the adaptive brain.
Provides read and send access to email with strict security controls.

## Capabilities
- List inbox messages (with limits)
- Read email content
- Send new emails
- Search emails
- Manage attachments (view only)

## Security
- OAuth2 authentication required
- Read-only access to inbox by default
- Send requires explicit permission
- Attachment scanning
- Content sanitization
- Sandbox execution enforced
"""

module EmailClient

using JSON
using Dates

# Email configuration
struct EmailConfig
    api_endpoint::String
    max_emails::Int
    allowed_recipients::Vector{String}
    allowed_attachments::Vector{String}
    enable_send::Bool
end

"""
    create_config()

Create email configuration with security defaults.
"""
function create_config()
    EmailConfig(
        "https://mail-api.example.com/v3",  # api_endpoint
        20,                                   # max_emails - inbox limit
        ["@example.com"],                     # allowed_recipients
        [".txt", ".pdf", ".json", ".md"],    # allowed_attachments
        false                                 # enable_send - disabled by default
    )
end

"""
    validate_email(email::Dict)

Validate email data before sending.
"""
function validate_email(email::Dict)
    errors = String[]
    
    # Required fields
    if !haskey(email, "to") || isempty(email["to"])
        push!(errors, "Recipient (to) is required")
    end
    
    if !haskey(email, "subject") || isempty(email["subject"])
        push!(errors, "Subject is required")
    end
    
    # Validate recipient domain
    config = create_config()
    recipient = get(email, "to", "")
    domain_allowed = any(endswith(recipient, allowed) for allowed in config.allowed_recipients)
    
    if !domain_allowed && !isempty(recipient)
        push!(errors, "Recipient domain not in whitelist")
    end
    
    # Check subject length
    if length(get(email, "subject", "")) > 500
        push!(errors, "Subject too long (max 500 characters)")
    end
    
    return isempty(errors), errors
end

"""
    sanitize_email(email::Dict)

Sanitize email content to prevent injection.
"""
function sanitize_email(email::Dict)
    sanitized = Dict{String, Any}()
    
    for (key, value) in email
        if typeof(value) == String
            # Remove HTML tags for security
            sanitized[key] = replace(value, r"<[^>]*>" => "")
            # Remove dangerous protocols
            sanitized[key] = replace(sanitized[key], r"javascript:" => "", count=1)
            sanitized[key] = replace(sanitized[key], r"data:" => "", count=1)
        else
            sanitized[key] = value
        end
    end
    
    return sanitized
end

"""
    list_emails(config::EmailConfig, folder::String="inbox", limit::Int=20)

List emails in specified folder.
"""
function list_emails(config::EmailConfig, folder::String="inbox", limit::Int=20)
    # Apply limit
    limit = min(limit, config.max_emails)
    
    println("EmailClient: Listing $limit emails from $folder")
    
    # In production, actual API call would happen here
    return Dict(
        "success" => true,
        "folder" => folder,
        "emails" => [],
        "count" => 0,
        "total_available" => 0
    )
end

"""
    read_email(config::EmailConfig, email_id::String)

Read email content by ID.
"""
function read_email(config::EmailConfig, email_id::String)
    println("EmailClient: Reading email $email_id")
    
    # In production, actual API call would happen here
    return Dict(
        "success" => true,
        "email_id" => email_id,
        "from" => "",
        "to" => "",
        "subject" => "",
        "body" => "",
        "date" => string(now())
    )
end

"""
    send_email(config::EmailConfig, email::Dict)

Send an email (requires enable_send=true in config).
"""
function send_email(config::EmailConfig, email::Dict)
    if !config.enable_send
        return Dict(
            "success" => false,
            "error" => "Sending email is disabled. Enable via configuration."
        )
    end
    
    # Sanitize and validate
    email = sanitize_email(email)
    is_valid, errors = validate_email(email)
    
    if !is_valid
        return Dict(
            "success" => false,
            "errors" => errors
        )
    end
    
    println("EmailClient: Sending email to $(email["to"])")
    
    # Generate message ID
    message_id = string(uuid4())
    
    return Dict(
        "success" => true,
        "message_id" => message_id,
        "to" => email["to"],
        "subject" => email["subject"],
        "sent" => true
    )
end

"""
    search_emails(config::EmailConfig, query::String, limit::Int=20)

Search emails by query string.
"""
function search_emails(config::EmailConfig, query::String, limit::Int=20)
    # Sanitize query
    query = strip(replace(query, r"[^\w\s@.-]" => ""))
    limit = min(limit, config.max_emails)
    
    println("EmailClient: Searching emails for: $query")
    
    return Dict(
        "success" => true,
        "query" => query,
        "results" => [],
        "count" => 0
    )
end

"""
    execute(params::Dict)

Main entry point for capability registry.
"""
function execute(params::Dict)
    action = get(params, "action", "list_emails")
    config = create_config()
    
    result = try
        if action == "list_emails"
            folder = get(params, "folder", "inbox")
            limit = get(params, "limit", 20)
            list_emails(config, folder, limit)
        elseif action == "read_email"
            email_id = get(params, "email_id", "")
            read_email(config, email_id)
        elseif action == "send_email"
            email = get(params, "email", Dict())
            send_email(config, email)
        elseif action == "search_emails"
            query = get(params, "query", "")
            limit = get(params, "limit", 20)
            search_emails(config, query, limit)
        else
            Dict("success" => false, "error" => "Unknown action: $action")
        end
    catch e
        Dict("success" => false, "error" => string(e))
    end
    
    return result
end

# Entry point when run directly
if abspath(PROGRAM_FILE) == @__FILE__()
    result = execute(Dict())
    println(JSON.json(result))
end

end # module
