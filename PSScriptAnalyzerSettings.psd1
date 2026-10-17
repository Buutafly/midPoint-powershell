@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The module builds the Basic auth header from a PSCredential; the password never leaves memory.
        'PSAvoidUsingPlainTextForPassword'
    )
}
